#!/bin/sh

# Defaults
MOD="quality"
PRE="6"
CRF="40"
TBR="3M"
TUN="5"
ADF="anull"

# Common constants
VDF='scale=if(lte(iw\,ih)\,min(iw\,1080)\,-1):if(lte(iw\,ih)\,-1\,min(ih\,1080)),crop=iw-mod(iw\,8):ih-mod(ih\,8)'
SVT='ac-bias=1.0:enable-cdef=1:enable-dlf=2:enable-kf-tf=1:enable-restoration=1:enable-tf=1:enable-variance-boost=1:lp=4:qp-scale-compress-strength=1:scd=1:scm=3:sharpness=1'

# Parse parameter block: :key1=val1:key2=val2:...:
parse_params() {
  BLK="${1#:}"
  BLK="${BLK%:}"
  SEP="${IFS}"
  IFS=':'
  # shellcheck disable=SC2086
  for KV in ${BLK}; do
    [ -z "${KV}" ] && continue
    KEY="${KV%%=*}"
    VAL="${KV#*=}"
    case "${KEY}" in
      mode|m)    MOD="${VAL}" ;;
      preset|p)  PRE="${VAL}" ;;
      quality|q) CRF="${VAL}" ;;
      bitrate|b) TBR="${VAL}" ;;
      tune|t)    TUN="${VAL}" ;;
    esac
  done
  IFS="${SEP}"
}

# Decide audio filter based on input audio channel count
audio_filter_args() {
  CHN="$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$1" 2>/dev/null)"
  case "${CHN}" in
    ''|*[!0-9]*) ADF="anull" ;;
    *)
      if [ "${CHN}" -gt 2 ]; then
        # shellcheck disable=SC2140
        ADF="sofalizer=sofa=""${PREFIX-:"/usr"}""/share/libmysofa/default.sofa:type=time:gain=6:interpolate=1"
      else
        ADF="anull"
      fi
      ;;
  esac
}

# 1-pass encoding
encode_quality() {
  VID="$1"
  audio_filter_args "${VID}"
  taskset -a f0 ffmpeg -i "${VID}" \
    -vf "${VDF}" \
    -af "${ADF}" \
    -c:v libsvtav1 -preset "${PRE}" -g 120 -bf 8 -refs 5 -crf "${CRF}" -pix_fmt yuv420p10le \
    -svtav1-params "${SVT}:rc=0:superres-mode=3:superres-qthres=$((CRF - 5)):tune=${TUN}" \
    -c:a libopus -ac 2 -b:a 76.8K \
    "!${VID}"
}

# 2-pass encoding
encode_bitrate() {
  VID="$1"
  taskset -a f0 ffmpeg -i "${VID}" \
    -vf "${VDF}" \
    -c:v libsvtav1 -preset "${PRE}" -g 120 -bf 8 -refs 5 -b:v "${TBR}" -pix_fmt yuv420p10le \
    -svtav1-params "${SVT}:rc=1:tune=${TUN}" -pass 1 \
    -an \
    -f null \
    "/dev/null"
  audio_filter_args "${VID}"
  taskset -a f0 ffmpeg -i "${VID}" \
    -vf "${VDF}" \
    -af "${ADF}" \
    -c:v libsvtav1 -preset "${PRE}" -g 120 -bf 8 -refs 5 -b:v "${TBR}" -pix_fmt yuv420p10le \
    -svtav1-params "${SVT}:rc=1:tune=${TUN}" -pass 2 \
    -c:a libopus -ac 2 -b:a 76.8K \
    "!${VID}"
}

if [ $# -eq 0 ]; then
  echo "Usage: zxc [ :key1=value1[:key2=value2...]: ] <video1 [video2 ...]>" >&2
  exit 1
fi

# Parameter block identified by leading ':' and trailing ':'
case "$1" in
  :*:)
    parse_params "$1"
    shift
    ;;
esac

for VID in "$@"; do
  case "${VID}" in
    !*) continue ;;
  esac
  [ -f "!${VID}" ] && continue
  case "${MOD}" in
    bitrate) encode_bitrate "${VID}" ;;
    *)       encode_quality "${VID}" ;;
  esac
done
