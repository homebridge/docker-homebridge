# Shared helpers that decide what an image update does to the Homebridge
# version in the volume.
#
# This file is sourced, not executed.

# Returns 0 when $1 is a plain version number such as 2.5.0 or 2.5.1-beta.4
hb_semver_valid() {
  printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z.-]+)?$'
}

# Compares two version numbers by the semver rules. Prints "lt" when $1 is
# lower than $2, "eq" when they are equal and "gt" when $1 is higher.
hb_semver_compare() {
  LC_ALL=C awk -v a="$1" -v b="$2" '
    function isnum(s) { return s ~ /^[0-9]+$/ }
    function cmpnum(x, y) { x += 0; y += 0; return x < y ? -1 : (x > y ? 1 : 0) }
    function cmpid(x, y) {
      if (isnum(x) && isnum(y)) return cmpnum(x, y)
      if (isnum(x)) return -1
      if (isnum(y)) return 1
      x = x ""; y = y ""
      return x < y ? -1 : (x > y ? 1 : 0)
    }
    function done(r) { print (r < 0 ? "lt" : (r > 0 ? "gt" : "eq")); exit 0 }
    BEGIN {
      sub(/\+.*$/, "", a); sub(/\+.*$/, "", b)
      pa = ""; pb = ""
      i = index(a, "-"); if (i > 0) { pa = substr(a, i + 1); a = substr(a, 1, i - 1) }
      i = index(b, "-"); if (i > 0) { pb = substr(b, i + 1); b = substr(b, 1, i - 1) }
      split(a, A, "."); split(b, B, ".")
      for (k = 1; k <= 3; k++) { r = cmpnum(A[k], B[k]); if (r != 0) done(r) }
      # a version with a pre-release part is lower than the same version without one
      if (pa == "" && pb == "") done(0)
      if (pa == "") done(1)
      if (pb == "") done(-1)
      na = split(pa, PA, "."); nb = split(pb, PB, ".")
      for (k = 1; k <= na && k <= nb; k++) { r = cmpid(PA[k], PB[k]); if (r != 0) done(r) }
      done(na - nb)
    }'
}

# Prints the release stream of a Docker Homebridge version: "stable" for
# 2026-11-15, "beta" for beta-2026-11-18 and so on. Prints nothing when the
# value is not in one of those two forms.
hb_stream_of() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) echo "stable" ;;
    ?*-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) echo "${1%-????-??-??}" ;;
  esac
}

# Decides what to do with the Homebridge version in the volume after an image
# update. Prints one word:
#   image   write the version of the image into the volume
#   keep    leave the version in the volume alone
# and the reason on a second line.
#   $1 version in the image    $2 version in the volume (may be empty)
#   $3 Docker Homebridge version the volume was last started with
#   $4 Docker Homebridge version of this image
hb_update_decision() {
  hb_volume_version=$(printf '%s' "$2" | sed 's/^[\^~=v]*//')
  hb_old_stream=$(hb_stream_of "$3")
  hb_new_stream=$(hb_stream_of "$4")

  if [ -z "$hb_volume_version" ] || [ "$hb_volume_version" = "null" ]; then
    printf 'image\n%s\n' "no Homebridge version is listed in the volume"
  elif [ -n "$hb_old_stream" ] && [ -n "$hb_new_stream" ] && [ "$hb_old_stream" != "$hb_new_stream" ]; then
    printf 'image\n%s\n' "the release stream changed from ${hb_old_stream} to ${hb_new_stream}"
  elif ! hb_semver_valid "$hb_volume_version"; then
    printf 'keep\n%s\n' "the volume holds a custom Homebridge version (${2})"
  elif [ "$(hb_semver_compare "$1" "$hb_volume_version")" = "gt" ]; then
    printf 'image\n%s\n' "the image holds a newer Homebridge (${1}) than the volume (${hb_volume_version})"
  else
    printf 'keep\n%s\n' "the volume already holds Homebridge ${hb_volume_version}, which is not older than the image (${1})"
  fi
}
