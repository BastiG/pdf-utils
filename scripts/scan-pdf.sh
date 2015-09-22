#!/bin/bash

# Scanner resolution
DPI=600
# Size (pixels) of A4 at 600 dpi
DPI_DIM=4960x7016

[ -z "${DEBUG}" ] && DEBUG=0

function log() {
	MESSAGE="${1}"

	if [[ ${DEBUG} -eq 1 ]]; then
		echo "${MESSAGE}"
	fi
}

LANG=deu
HOCR2PDF=HocrConverter.py

BATCH=1
START_NAME=1
FAXMODE=0
OPEN_FILE=1
USE_OCR=1
OPT_AS_OCR_SOURCE=0

# Print command usage
function print_usage() {
    cat <<EOF
USAGE: $(basename "${0}") [OPTIONS] [FILENAME]
Options:
    -h|--help    This message
    -f|--fax     Fax mode
    -q|--quality Optimize scanned pages
    -n|--no-ocr  Don't run character recognition
    -o|--no-open Don't open the scanned file
    -s|--single  Don't use batch mode
EOF
    exit 0
}

function evaluate_flag() {
    case "${1}" in
        h|--help)
            print_usage
            ;;
        s|--single)
            log "Don't use batch mode"
            START_NAME=1
            BATCH=0
            ;;
        n|--no-ocr)
            log "Not running OCR"
            USE_OCR=0
            ;;
        f|--fax)
            log "Optimize for faxing"
            FAXMODE=1
            ;;
        q|--quality)
            log "Optimize for viewing quality"
            OPT_AS_OCR_SOURCE=1
            ;;
        o|--no-open)
            log "Open result file"
            OPEN_FILE=0
            ;;
        *)
            echo "Uknown flag - ignoring -${1}"
            ;;
    esac
}

# Process command line
# Treat everyting as flag until reading the first non-flag
while [ ${#} -gt 0 ]; do
    if [ ${START_NAME} -eq 1 ]; then
        if [[ ${1} == --* ]]; then
            evaluate_flag "${1}"
        elif [[ ${1} == -* ]]; then
            FLAGS="${1:1}"
            while read FLAG
            do
                evaluate_flag "${FLAG}"
            done < <(echo -n "${FLAGS}" | sed 's/\(.\)/\1\n/g')
        else
            FILENAME="${1}"
            START_NAME=0
        fi
    else
        FILENAME="${FILENAME} ${1}"
    fi
	shift
done

# Generate a file name if none was provided
if [ "${FILENAME}" == "" ]; then
	DATETIME=$(date +%F_%H%M%S)
	FILENAME=scan-${DATETIME}
else
	if [[ -e "${FILENAME}.pdf" ]]; then
		I=2
		while [[ -e "${FILENAME}-${I}.pdf" ]]; do
			let I++
		done
		FILENAME="${FILENAME}-${I}"
	fi
fi

# Filename sanity check
CHK_FILE=$(basename "./${FILENAME}")
if [[ "${FILENAME}" != "${CHK_FILE}" ]]; then
	echo "Invalid filename: ${FILENAME}"
	exit 2
fi

log "Filename = ${FILENAME}"

# Temp dir will hold the scans
TMPDIR="/tmp/scan-${FILENAME}"
TMPFILE="${TMPDIR}/scan"

if [ -d "${TMPDIR}" ]; then
	rm -rf "${TMPDIR}"
fi
mkdir "${TMPDIR}"

###############################################################################
# Scan function
# Parameters
# - SCAN_FILE : the process will scan the image to this file
###############################################################################
function do_scan() {
	SCAN_FILE="${1}"

	log "Scanning to ${SCAN_FILE}"

    if [ ${FAXMODE} -eq 0 ]; then
    	GENERAL="--resolution=${DPI} --depth=8 --mode=COLOR"
    else
        GENERAL="--resolution=${DPI} --depth=8 --mode=LINEART"
    fi

	AREA="-l 1 -t 1 -x 208 -y 295"
	FORMAT="--format=tiff"
	IMPROVE="--disable-interpolation=yes"
	INTERFACE="--progress"
	#SPECIAL="-v"

	SCAN_OPTS="${DEVICE} ${GENERAL} ${AREA} ${IMPROVE} ${INTERFACE} ${FORMAT} ${SPECIAL}"

	scanimage ${SCAN_OPTS} > "${SCAN_FILE}"

	if [ $? -eq 0 ] && [[ -e "${SCAN_FILE}" ]]; then
		return 0
	else
		return 1
	fi
}

###############################################################################
# Optimize the scanned file, prepare for OCR
# Parameters:
# - SCAN_FILE : the raw scan file
# - OCR_FILE : temporary file optimized for OCR
# - OPT_FILE : temporary file optimized for clarity
# - OCR_OPT_FILE : temporary file composed of the two files above
###############################################################################
function do_convert() {
	SCAN_FILE="${1}"
	OCR_FILE="${2}"
	OPT_FILE="${3}"
	OCR_OPT_FILE="${4}"
	OCR_TMP_FILE="${OCR_FILE}.mpc"

	log "Converting from ${SCAN_FILE} via ${OCR_FILE} and ${OPT_FILE} to ${OCR_OPT_FILE}"

    if [ ${FAXMODE} -eq 0 ]; then
    	IMPROVE_OPT="-channel RGB -contrast-stretch 0.5x10% -level 0%,90%,1.4 -deskew 60%"
    else
        IMPROVE_OPT="-channel RGB -contrast-stretch 2x10% -level 0%,90%,1.6 -deskew 60%"
    fi
	AREA="+repage -gravity center -background white -extent ${DPI_DIM}"

	convert "${SCAN_FILE}" ${IMPROVE_OPT} ${AREA} "${OPT_FILE}"

	convert -quiet -regard-warnings "${OPT_FILE}" +repage "${OCR_TMP_FILE}"
	convert -respect-parenthesis \( "${OCR_TMP_FILE}" -colorspace gray -type grayscale -contrast-stretch 0 \) \
		\( -clone 0 -colorspace gray -negate -lat 50x50+20% -contrast-stretch 0 \) \
		-compose copy_opacity -composite -fill "white" -opaque none +matte \
		-sharpen 0x1 -modulate 100,200 -adaptive-blur 5 \
	        "${OCR_FILE}"

    if [ ${FAXMODE} -eq 0 ]; then
    	convert "${OPT_FILE}" \
	    	\( "${OCR_FILE}" -normalize +level 0,30% \) \
		    -compose screen -composite -contrast-stretch 0.75% \
    		"${OCR_OPT_FILE}"
    else
        convert "${OPT_FILE}" \
            \( "${OCR_FILE}" -normalize +level 0,30% \) \
            -compose screen -composite -contrast-stretch 2x2% \
            "${OCR_OPT_FILE}"
    fi
}

###############################################################################
# Create a PDF from the scanned file
# Parameters:
# - OCR_FILE : OCR input as image file
# - PDF_NAME : basename of PDF to generate (no .pdf extension!)
###############################################################################
function do_ocr() {
	OCR_FILE="${1}"
    OPT_FILE="${2}"
    OCR_OPT_FILE="${3}"
	PDF_NAME="${4}"

	log "OCR ${OCR_FILE} to ${PDF_NAME}.pdf"

    if [ ${FAXMODE} -eq 0 ]; then
        if [ ${OPT_AS_OCR_SOURCE} -eq 0 ]; then
            IMG_FILE="${OPT_FILE}"
        else
            IMG_FILE="${OCR_OPT_FILE}"
        fi
    else
        IMG_FILE="${OCR_OPT_FILE}"
    fi

    if [ ${USE_OCR} -eq 1 ]; then
#       OCR to PDF currently broken with gs, disabled for the time being
#       http://bugs.ghostscript.com/show_bug.cgi?id=696116
#    	tesseract "${OCR_FILE}" "${PDF_NAME}" -l deu pdf
        tesseract "${OCR_FILE}" "${PDF_NAME}" -l "${LANG}" hocr
        "${HOCR2PDF}" -V -I -i "${PDF_NAME}.hocr" -o "${PDF_NAME}.pdf" \
            "${IMG_FILE}"
    else
        convert "${IMG_FILE}" "${PDF_NAME}.pdf"
    fi
}

###############################################################################
# Merge all single page PDF files into one multi-page document.
# Let ghostscript fix any issues it finds.
# Parameters:
# - PDF_IN : list of single page PDF files
# - PDF_OUT : output PDF file name
###############################################################################
function do_fixpdf() {
	PDF_IN=("${!1}")
	PDF_OUT="${2}"

	log "GS ${PDF_IN[*]} to ${PDF_OUT}"

	DEVICE="-sDEVICE=pdfwrite"
	AREA="-sPAPERSIZE=a4 -dFIXEDMEDIA -dPDFFitPage"
	GENERAL="-dBATCH -dNOPAUSE -dNOPAGEPROMPT"
	FORMAT="-dCompatibilityLevel=1.5"
	IMAGE_OPTS="-dAutoFilterColorImages=false -dColorImageFilter=/DCTEncode \
		-dDownsampleColorImages=true -dColorImageDownsampleType=/Average \
		-dColorImageDownsampleThreshold=1.5 -dColorImageResolution=300"

	GS_OPTS="${GENERAL} ${DEVICE} ${AREA} ${FORMAT} ${IMAGE_OPTS}"

	gs ${GS_OPTS} -sOutputFile="${PDF_OUT}" "${PDF_IN[@]}"
}

###############################################################################
# Delete temporary files
# Parameters:
# - TMP_DIR : the directory 
###############################################################################
function do_cleanup() {
	TMP_DIR="${1}"

	if [[ ${DEBUG} -eq 1 ]]; then
		log "Not cleaning up temporary directory ${TMP_DIR}"
	else
		rm -rf "${TMP_DIR}"
	fi
}

WANT_MORE=1
INDEX=0
PDFLIST=()

echo -e "Press any key to start scanning\a"
stty -echo
IFS= read -n1 kbd
stty echo

# Main scan loop
while [ ${WANT_MORE} -eq 1 ]; do
	WANT_MORE=${BATCH}

	let INDEX=${INDEX}+1

	echo "Scanning page ${INDEX}"

	START=$(date +%s.%N)

	PAGE_FILE="${TMPFILE}-${INDEX}"

	do_scan "${PAGE_FILE}.tif"

	if [ $? -ne 0 ]; then
		echo "[ERROR] Failed to scan page ${INDEX}"
		break
	fi

	END=$(date +%s.%N)
	SCAN_DIFF=$(echo "($END - $START) / 1" | bc)

    OCR_IN="${PAGE_FILE}-ocr-opt.tif"
    if [ ${OPT_AS_OCR_SOURCE} -eq 1 ]; then
        OCR_IN="${PAGE_FILE}-opt.tif"
    fi
	do_convert "${PAGE_FILE}.tif" "${PAGE_FILE}-ocr.tif" "${PAGE_FILE}-opt.tif" "${PAGE_FILE}-ocr-opt.tif"
	do_ocr "${PAGE_FILE}-ocr.tif" "${PAGE_FILE}-opt.tif" "${PAGE_FILE}-ocr-opt.tif" "${PAGE_FILE}.tmp"

	PDFLIST=("${PDFLIST[@]}" "${PAGE_FILE}.tmp.pdf")

    # Scan more?
	VALID_INPUT=0
	stty -echo
	while [ ${BATCH} -eq 1 ] && [ ${VALID_INPUT} -eq 0 ]; do
		echo -ne "Continue scanning?\a [Y/n] "
		IFS= read -n1 kbd
		case "${kbd}" in
			y|Y)
				WANT_MORE=1
				VALID_INPUT=1
				;;
			"")
				WANT_MORE=1
				VALID_INPUT=1
				;;
			n|N)
				WANT_MORE=0
				VALID_INPUT=1
				;;
			*)
				echo
				VALID_INPUT=0
				;;
		esac
	done
	stty echo
	echo
done

# Merge all single page PDF files
if [ ${#PDFLIST[@]} -eq 0 ]; then
	echo "[ERROR] No scans found, no output generated"
else
	do_fixpdf "PDFLIST[@]" "${FILENAME}.pdf"
fi

do_cleanup "${TMPDIR}"

END=$(date +%s.%N)
ALL_DIFF=$(echo "($END - $START) / 1" | bc)

echo "Operation completed in ${ALL_DIFF} seconds (${SCAN_DIFF} seconds for scanning)"

if [ ${#PDFLIST[@]} -ne 0 ]; then
	echo "Scanned to ${FILENAME}.pdf"
fi

if [ ${OPEN_FILE} -ne 0 ]; then
    xdg-open "${FILENAME}.pdf" >/dev/null 2>&1
fi
