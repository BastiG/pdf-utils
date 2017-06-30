#!/bin/env python

import os
import sane
import tempfile
import threading
import argparse
import subprocess

import shutil
import time
import re
import pwd

from PIL import Image

MIN_SEVERITY = 1
DEPTH = 8
MODE = 'color'
ADF = 'ADF'
DEVICE_NAME = 'MFP_M277'
DPI = 300
COMPRESSION = 'None'
DIM_DPI = '2480x3508'
LANG = 'deu'
HOCR2PDF = 'HocrConverter.py'

class ScanIterator:
    """
    Iterator for ADF scans.
    """

    def __init__(self, device):
        self.device = device
        self.__count = 0

    def __iter__(self):
        return self

    def __del__(self):
        try:
            self.device.cancel()
        except:
            pass

    def __next__(self):
        while True:
            try:
                self.device.start()
            except Exception as e:
                if str(e) == 'Document feeder out of documents':
                    if self.__count == 0:
                        continue
                    raise StopIteration
                else:
                    raise
            
            self.__count += 1
            return self.device.snap(True)

    def count(self):
        return self.__count


def output(severity, message):
    if severity < MIN_SEVERITY:
        return
    
    print(message)

def scanner_by_name(dev_name):
    devices = sane.get_devices()
    for (url, vendor, name, type) in devices:
        if dev_name in name:
            output(1, 'Selected scanner {} {} ({})'.format(vendor, dev_name, type))
            return sane.open(url)

    return None

def call_shell(command):
    p = subprocess.Popen(command, shell=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate()
    if (p.returncode != 0):
        print('Command {cmd} returned {code}.'.format(cmd=command, code=p.returncode))
        print(err.decode('utf-8'))


class ProcessingThread (threading.Thread):
    def __init__(self, basename, with_ocr):
        threading.Thread.__init__(self)
        self.basename = basename
        self.with_ocr = with_ocr

    def ocr(self):
        ocrfile = self.basename + '.ocr-opt.png'
        imagefile = self.basename + '.ocr-opt.png'
        if (self.with_ocr):
            call_shell('tesseract "{imagefile}" "{outfile}" -l "{lang}" hocr'.format(
                imagefile=ocrfile, outfile=self.basename, lang=LANG))
            
            call_shell('{hocr2pdf} -V -I -q -i "{hocrfile}.hocr" -o "{outfile}.pdf" "{imagefile}"'.format(
                hocr2pdf=HOCR2PDF, hocrfile=self.basename, outfile=self.basename, imagefile=imagefile))
        else:
            call_shell('convert "{imagefile}" "{outfile}.pdf"'.format(
                imagefile=imagefile, outfile=self.basename))

    def convert(self):
        scanfile = self.basename + '.png'
        opt_file = self.basename + '.opt.png'
        ocr_file = self.basename + '.ocr.png'
        ocr_tmp_file = self.basename + '.mpc'
        ocr_opt_file = self.basename + '.ocr-opt.png'
        
        call_shell(('convert -units PixelsPerInch "{scanfile}" '
            '-channel RGB -contrast-stretch 0.5x10% -level 0%,90%,1.4 '
            '-deskew 60% +repage -gravity center -background white '
            '-extent {dim_dpi} -density {dpi} "{opt_file}"').format(
                scanfile=scanfile, dim_dpi=DIM_DPI, dpi=DPI, opt_file=opt_file))
        call_shell(('convert -quiet -regard-warnings "{opt_file}" '
            '+repage "{ocr_tmp_file}"').format(
                opt_file=opt_file, ocr_tmp_file=ocr_tmp_file))
        call_shell(('convert -respect-parenthesis \( "{ocr_tmp_file}" '
            '-colorspace gray -type grayscale -contrast-stretch 0,10% \) '
            '\( -clone 0 -colorspace gray -negate -lat 50x50+20% '
            '-contrast-stretch 0 \) -compose copy_opacity -composite '
            '-fill "white" -opaque none -alpha off -sharpen 0x1 '
            '-modulate 100,200 -statistic Minimum 2x2 "{ocr_file}"').format(
                ocr_tmp_file=ocr_tmp_file, ocr_file=ocr_file))
        call_shell(('convert "{opt_file}" \( "{ocr_file}" -normalize '
            '+level 0,10% \) -compose screen -composite '
            '-contrast-stretch 0.75% "{ocr_opt_file}"').format(
                opt_file=opt_file, ocr_file=ocr_file, ocr_opt_file=ocr_opt_file))
        
    def run(self):
        self.convert()
        self.ocr()

def scan_single_page(path, front, scan, multi_scan):
    if (front):
        type = 'page'
        ab = 'a'
    else:
        type = 'rear'
        ab = 'b'

    filename = '{path}/{type}-{index:06}-{ab}'.format(
        path=path, type=type, index=multi_scan.count(), ab=ab)
    scan.save(filename+'.png')

    return filename

def process_single_page(filename, ocr):
    processor = ProcessingThread(filename, ocr)
    processor.start()
    return processor

def scan_adf(dev_name, duplex, ocr, path):
    sane.init()
    
    scanner = scanner_by_name(dev_name)
    if scanner is None:
        return
    
    scanner.depth = DEPTH
    scanner.mode = MODE
    scanner.source = ADF
    scanner.resolution = DPI
    scanner.compression = COMPRESSION
    
    scanner.tl_x = 2
    scanner.tl_y = 2
    scanner.br_x = 206
    scanner.br_y = 293
    
    print('Ready to scan')
    
    pages = []
    threads = []
    
    multi_scan = ScanIterator(scanner)
    for scan in multi_scan:
        filename = scan_single_page(path, True, scan, multi_scan)
        pages.append(filename)
        threads.append(process_single_page(filename, ocr))
    
    if multi_scan.count() == 0:
        output(4, 'Nothing scanned, exiting')
        scanner.close()
        return []
    
    if duplex:
        output(4, 'Front pages done, please turn sheets')
        
        rear_pages = []
        
        multi_scan = ScanIterator(scanner)
        for scan in multi_scan:
            filename = scan_single_page(path, False, scan, multi_scan)
            rear_pages.append(filename)
            threads.append(process_single_page(filename, ocr))

        scanner.close()
        for t in threads:
            t.join()

        rear_pages.reverse()
        index = 1

        for filename in rear_pages:
            target = '{}/page-{:06}-b'.format(path, index)
            os.rename(filename+'.pdf', target+'.pdf')
            pages.append(target)
            index = index + 1
    else:
        scanner.close()
        for t in threads:
            t.join()
    
    pages.sort()
    return pages

def build_pdf(pages, name, pdf_marks):
    
    filename = name.replace('/', '_') + '.pdf'
    index = 1
    
    while (os.path.exists(filename)):
        index = index + 1
        filename = '{base} ({index}).pdf'.format(
            base=name.replace('/', '_'), index = index)

    print('Creating file {filename}'.format(filename=filename))
    
    call_shell(('gs -dBATCH -dNOPAUSE -dNOPAGEPROMPT -sDEVICE=pdfwrite '
        '-sPAPERSIZE=a4 -dFIXEDMEDIA -dPDFFitPage -dCompatibilityLevel=1.5 '
        '-dAutoFilterColorImages=false -dColorImageFilter=/DCTEncode '
        '-dDownsampleColorImages=true -dColorImageDownsampleType=/Average '
        '-dColorImageDownsampleThreshold=1.5 -dColorImageResolution=300 '
        '-sOutputFile="{file_out}" "{pages_in}.pdf" "{pdf_marks}"').format(
            file_out=filename, pages_in='.pdf" "'.join(pages),
            pdf_marks = pdf_marks))
            
    return filename

def clean_up(path):
    sane.exit()
    shutil.rmtree(path)

parser = argparse.ArgumentParser(description='Scan a document')
parser.add_argument('-1', '--single-side', dest='duplex', action='store_false',
    default=True, help='scan single-sided document, default is duplex')
parser.add_argument('-o', '--no-ocr', dest='ocr', action='store_false',
    default=True, help='disables optical character recognition, default is on')
parser.add_argument('-v', '--no-view', dest='view', action='store_false',
    default=True, help='don\'t show generated file, shown by default')
parser.add_argument('name', metavar='title', nargs='+', help='document title')
args = parser.parse_args()

name = ' '.join(args.name)
author = pwd.getpwuid(os.getuid())[4]
now_time = time.strftime("%Y%m%d%H%M%S")

parts = name if len(args.name) > 1 else name.split(' ')

m = re.search(r'\d{6,8}', args.name[0])
if m:
    subject = ' '.join(args.name[1:])
    name_date = args.name[0].ljust(8, '0')
else:
    subject = name
    name_date = time.strftime("%Y%m%d000000")

path = tempfile.mkdtemp()
pdf_marks = path + '/pdfmarks'
with open(pdf_marks, mode='w') as f:
    f.write('[ /Title <FEFF{title}>\n'
        '  /Author <FEFF{author}>\n'
        '  /Subject <FEFF{subject}>\n'
        '  /Keywords ()\n'
        '  /ModDate (D:{moddate})\n'
        '  /CreationDate (D:{cdate})\n'
        '  /Creator (scan-pdf)\n'
        '  /Producer (scan-pdf)\n'
        '  /DOCINFO pdfmark\n'.format(
            title=''.join(format(x, '02x') for x in name.encode('utf-16be')),
            author=''.join(format(x, '02x') for x in author.encode('utf-16be')),
            subject=''.join(format(x, '02x') for x in subject.encode('utf-16be')),
            moddate=now_time, cdate=name_date))

#print(pdf_marks)
#exit(0)

pages = scan_adf(DEVICE_NAME, args.duplex, args.ocr, path)
filename = build_pdf(pages, name, pdf_marks)

clean_up(path)

if (args.view):
    Popen('xdg-open "{name}"'.format(name=filename),
        shell=True, stdout=PIPE, stderr=PIPE)
else:
    print('Scanned to {file}'.format(file=filename))