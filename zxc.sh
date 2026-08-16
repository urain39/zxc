#!/bin/sh

# Defaults
VER="1.0.0"
MOD="q"
PRE="6"
CRF="40"
VBR="3M"
ABR="76.8K"
FPS="30"
OWM=""
ASS=""
TUN=""
ADF=""
OUT="/dev/null"

# Common constants
VDF='scale=if(lte(iw\,ih)\,min(iw\,1080)\,-1):if(lte(iw\,ih)\,-1\,min(ih\,1080)),crop=iw-mod(iw\,8):ih-mod(ih\,8)'
SOF="${HOME}/.local/share/zxc/default.sofa"
SVT='ac-bias=1.0:enable-cdef=1:enable-dlf=2:enable-kf-tf=1:enable-restoration=1:enable-tf=1:enable-variance-boost=1:lp=4:qp-scale-compress-strength=1:scd=1:scm=3:sharpness=1'

# Extract embedded SOFA file
ensure_sofa() {
  if [ ! -f "${SOF}" ]; then
    mkdir -p "${SOF%/*}"
    sed '1,/^#@DEFAULT_SOFA@$/d' "$0" | base64 -d > "${SOF}"
  fi
}

show_help() {
  # NOTE: Do not use this function after encoding starts, as default values might be changed.
  cat << EOF
zxc v${VER}

Usage: zxc [ :key1=value1[:key2=value2...]: ] <video1 [video2 ...]>

Encodes videos using libsvtav1 and libopus. Output files are prefixed with '!' and include
configuration suffixes, preserving the original file extension.

Options are specified in a colon-delimited block at the beginning.
Example: zxc :mode=b:preset=4:bitrate=2M: video.mkv

Available keys:
  mode|m             Encoding mode. "q[uality]" (1-pass CRF) or "b[itrate]" (2-pass ABR). Default: ${MOD}
  preset|p           SVT-AV1 preset (0-13, lower is slower/better). Default: ${PRE}
  quality|q          CRF value (0-63, lower is better). Used in quality mode. Default: ${CRF}
  bitrate|vb|b       Target video bitrate. Used in bitrate mode. Default: ${VBR}
  audio-bitrate|ab|B Target audio bitrate. Used in both quality and bitrate modes. Default: ${ABR}
  fps|f              Output frame rate cap. Default: ${FPS}
  overwrite|ow|w     Overwrite mode: y or n. Default: ${OWM:-"<empty>"}
  tune|t             SVT-AV1 tune parameter. Default: ${TUN:-"5 for quality, 0 for bitrate"}
EOF
}

# Parse parameter block: :key1=val1:key2=val2:...:
parse_params() {
  BLK="${1#:}"
  BLK="${BLK%:}"
  SEP="${IFS}"
  IFS=':'
  for PKV in ${BLK}; do
    [ -z "${PKV}" ] && continue
    KEY="${PKV%%=*}"
    VAL="${PKV#*=}"
    case "${KEY}" in
      mode|m)             MOD="${VAL}" ;;
      preset|p)           PRE="${VAL}" ;;
      quality|q)          CRF="${VAL}" ;;
      bitrate|vb|b)       VBR="${VAL}" ;;
      audio-bitrate|ab|B) ABR="${VAL}" ;;
      fps|f)              FPS="${VAL}" ;;
      overwrite|ow|w)     OWM="${VAL}" ;;
      tune|t)             TUN="${VAL}" ;;
    esac
  done
  IFS="${SEP}"
}

# Decide stream mapping and audio filter based on input streams
prepare_map() {
  # NOTE: Explicit reset is required as ADF might be set by previous file
  ADF="anull"
  read -r ASS MCH << INFO
$(ffprobe -v error -select_streams a -show_entries stream=channels,bit_rate -of csv=p=0 "${VID}" | awk -F, '{ w = $1 * 10 + $2 / 64000; if (w > m) { m = w; i = NR - 1; c = $1 } } END { if (NR > 0) print i, c }')
INFO
  ASS="${ASS:-"0"}"
  case "${MCH}" in
    [3-9]|[1-9][0-9])
      ensure_sofa
      ADF="dynaudnorm,sofalizer=sofa=${SOF}:type=time:gain=-10:interpolate=1,volume=10dB"
      ;;
  esac
}

# 1-pass encoding
encode_quality() {
  OUT="${DIR}/!${FIL%.*}_p${PRE},q${CRF},B${ABR},t${TUN}.${FIL##*.}"
  [ "${OWM}" != "y" ] && [ -f "${OUT}" ] && return 0
  prepare_map
  taskset -a f0 ffmpeg ${OWM:+"-${OWM}"} -i "${VID}" \
    -map "0:v:0" -map "0:a:${ASS}?" -map "0:s?" -map "0:t?" -map "0:d?" \
    -map_chapters 0 -map_metadata 0 -metadata comment="Encoded with zxc v${VER} (Quality)" \
    -vf "${VDF},fps=min(source_fps\,${FPS})" \
    -af "${ADF}" \
    -c:v libsvtav1 -preset "${PRE}" -g 120 -bf 8 -refs 5 -crf "${CRF}" -pix_fmt yuv420p10le \
    -svtav1-params "${SVT}:rc=0:superres-mode=3:superres-qthres=$((CRF - 5)):tune=${TUN}" \
    -c:a libopus -ac 2 -b:a "${ABR}" \
    -c:s copy -c:t copy -c:d copy \
    "${OUT}"
}

# 2-pass encoding
encode_bitrate() {
  OUT="${DIR}/!${FIL%.*}_p${PRE},b${VBR},B${ABR},t${TUN}.${FIL##*.}"
  [ "${OWM}" != "y" ] && [ -f "${OUT}" ] && return 0

  # Unique passlog prefix to avoid conflicts and ensure cleanup
  PAS="${OUT}.pass"

  prepare_map

  taskset -a f0 ffmpeg ${OWM:+"-${OWM}"} -i "${VID}" \
    -map "0:v:0" \
    -vf "${VDF},fps=min(source_fps\,${FPS})" \
    -c:v libsvtav1 -preset "${PRE}" -g 120 -bf 8 -refs 5 -b:v "${VBR}" -pix_fmt yuv420p10le \
    -svtav1-params "${SVT}:rc=1:tune=${TUN}" -pass 1 -passlogfile "${PAS}" \
    -an \
    -f null \
    "/dev/null" || { rm -f "${PAS}"-*.log*; return 1; }

  taskset -a f0 ffmpeg ${OWM:+"-${OWM}"} -i "${VID}" \
    -map "0:v:0" -map "0:a:${ASS}?" -map "0:s?" -map "0:t?" -map "0:d?" \
    -map_chapters 0 -map_metadata 0 -metadata comment="Encoded with zxc v${VER} (Bitrate)" \
    -vf "${VDF},fps=min(source_fps\,${FPS})" \
    -af "${ADF}" \
    -c:v libsvtav1 -preset "${PRE}" -g 120 -bf 8 -refs 5 -b:v "${VBR}" -pix_fmt yuv420p10le \
    -svtav1-params "${SVT}:rc=1:tune=${TUN}" -pass 2 -passlogfile "${PAS}" \
    -c:a libopus -ac 2 -b:a "${ABR}" \
    -c:s copy -c:t copy -c:d copy \
    "${OUT}" || { rm -f "${PAS}"-*.log*; return 1; }

  # Remove 2-pass log files after encoding
  rm -f "${PAS}"-*.log*
}

if [ "$#" = "0" ]; then
  show_help
  exit 1
fi

case "$1" in
  -h|--help) show_help; exit 0 ;;
esac

# Parameter block identified by leading ':' and trailing ':'
case "$1" in
  :*:)
    parse_params "$1"
    shift
    ;;
esac

for VID in "$@"; do
  FIL="${VID##*/}"
  DIR="${VID%/*}"
  [ "${DIR}" = "${FIL}" ] && DIR="."
  case "${FIL}" in
    !*) continue ;;
  esac
  case "${MOD}" in
    q*) TUN="${TUN:-"5"}"; encode_quality ;;
    b*) TUN="${TUN:-"0"}"; encode_bitrate ;;
    *)  show_help; exit 1 ;;
  esac
done

exit 0

#@DEFAULT_SOFA@
