#!/bin/sh

function print_usage() {
	echo "USAGE: $0 [-s|-p] input1.pdf [input2.pdf input3.pdf ...] output.pdf"
	echo "       -s : Screen resolution (72dpi), results in smaller files"
	echo "       -m : Medium resolution (150dpi)"
	echo "       -p : Printer resolution (300dpi), results in larger files"
}

PDFSETTINGS="/default"

if [ "$1" == "-s" ]; then
	PDFSETTINGS="/screen"
	shift
elif [ "$1" == "-m" ]; then
	PDFSETTINGS="/ebook"
	shift
elif [ "$1" == "-p" ]; then
#	PDFSETTINGS="/printer"
	PDFSETTINGS="/prepress"
	shift
fi

if [ $# -lt 2 ]; then
	print_usage
	exit 2
fi

INPUT=("$1")
shift

while [ $# -gt 1 ]; do
	INPUT=("${INPUT[@]}" "$1")
	shift
done

OUTPUT="$1"

# echo "Input: ${INPUT[*]}"
# echo "Output: ${OUTPUT}"

# exit

gs -sDEVICE=pdfwrite -dCompantibilityLevel=1.4 -dPDFSETTINGS=${PDFSETTINGS} -dNOPAUSE -dQUIET -sOutputFile=${OUTPUT} -dBATCH "${INPUT[@]}"
