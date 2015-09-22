#!/usr/bin/env python
# -*- coding: utf-8 -

from PyPDF2 import PdfFileWriter, PdfFileReader
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from reportlab.lib.colors import Color
from reportlab.pdfbase.pdfmetrics import stringWidth
from io import BytesIO
from os.path import splitext, isfile
import subprocess
import argparse

parser = argparse.ArgumentParser(description='Add watermark to a PDF file')
parser.add_argument('inFile', help='input PDF')
parser.add_argument('watermark', help='text to be printed as watermark')
parser.add_argument('outFile', nargs='?', help='output PDF [default=inFile.stamped.pdf]')
parser.add_argument('-a', '--alpha', default=0.6, type=float, help='the alpha value of the watermark')
parser.add_argument('-R', '--red', default=0, type=int, help='the red aspect of the color of the watermark')
parser.add_argument('-G', '--green', default=0, type=int, help='the green aspect of the color of the watermark')
parser.add_argument('-B', '--blue', default=0, type=int, help='the blue aspect of the color of the watermark')
parser.add_argument('-f', '--font', default='Courier-Bold', help='the font of the watermark')
parser.add_argument('-s', '--fontSize', default=16, type=int, help='the size of the watermark font')
parser.add_argument('-p', '--pageSize', default=A4, help='the size of the page')
parser.add_argument('-o', '--open', action='store_true', help='open the new document')
parser.add_argument('-c', '--separator-char', default='•', help='separator char [default=•]')#
parser.add_argument('-r', '--separator-repeat', default=3, type=int, help='number of times the separator is repeated')

args = parser.parse_args()

pageWidth, pageHeight = args.pageSize
margin = 10

if not isfile(args.inFile):
    print('Error file %s does not exist' % args.inFile)
    exit(1)

if args.outFile is not None:
    outFile = args.outFile
else:
    outFile = splitext(args.inFile)[0] + '.stamped.pdf'
    print('Generating output file: %s' % outFile)

input = PdfFileReader(open(args.inFile, 'rb'))
output = PdfFileWriter()

sepText = args.separator_char[0] * args.separator_repeat
sepBlanks = ' ' * 3

text = sepText + sepBlanks + args.watermark + sepBlanks + sepText
addText = sepBlanks + args.watermark + sepBlanks + sepText

textWidth = stringWidth(text, args.font, args.fontSize)

while textWidth + 2 * margin < pageWidth:
    text = text + addText
    textWidth = stringWidth(text, args.font, args.fontSize)

packet = BytesIO()
can = canvas.Canvas(packet, pagesize=args.pageSize)
can.setStrokeColorRGB(args.red, args.green, args.blue)
can.setFillColor(Color(args.red, args.green, args.blue, alpha=args.alpha))
can.setFont(args.font, args.fontSize)
can.drawCentredString(pageWidth/2, margin, text)
can.drawCentredString(pageWidth/2, pageHeight-args.fontSize-margin, text)
can.save()
packet.seek(0)

watermarkFile = PdfFileReader(packet)
watermark = watermarkFile.getPage(0)

for pageNum in range(input.getNumPages()):
    page = input.getPage(pageNum)
    page.mergePage(watermark)
    output.addPage(page)

outputStream = open(outFile, 'wb')
output.write(outputStream)

if args.open:
    subprocess.call(['xdg-open', outFile])
