#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: generate-mlfs-ents.sh [version] [--suffix N] [--output-dir DIR]
                             [--packages-html FILE] [--patches-html FILE]

Generate MLFS-flavored copies of packages.ent and patches.ent.

If [version] is omitted, the script prompts for it. By default it writes:
  packages-2.ent
  patches-2.ent

Examples:
  ./generate-mlfs-ents.sh 13.0-m32
  ./generate-mlfs-ents.sh 13.0-m32 --suffix test --output-dir /tmp/out
  ./generate-mlfs-ents.sh 13.0-m32 \
    --packages-html /tmp/packages.html \
    --patches-html /tmp/patches.html
EOF
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

slugify_term() {
  local term=$1

  TERM_VALUE=$term perl -e '
    my $s = lc $ENV{TERM_VALUE};
    $s =~ s/[^a-z0-9]+/-/g;
    $s =~ s/^-+//;
    $s =~ s/-+$//;
    print $s;
  '
}

package_base_from_term() {
  local term=$1
  local slug

  slug=$(slugify_term "$term")

  case "$slug" in
    d-bus)
      printf '%s' "dbus"
      ;;
    procps)
      printf '%s' "procps-ng"
      ;;
    python-documentation)
      printf '%s' "python-docs"
      ;;
    sqlite-documentation)
      printf '%s' "sqlite-doc"
      ;;
    systemd-man-pages)
      printf '%s' "systemd-man"
      ;;
    tcl-documentation)
      printf '%s' "tcl-docs"
      ;;
    time-zone-data)
      printf '%s' "tzdata"
      ;;
    xz-utils)
      printf '%s' "xz"
      ;;
    *)
      printf '%s' "$slug"
      ;;
  esac
}

major_minor() {
  local version=$1
  local major minor rest
  IFS=. read -r major minor rest <<<"$version"
  if [[ -z ${major:-} || -z ${minor:-} ]]; then
    return 1
  fi
  printf '%s.%s' "$major" "$minor"
}

sqlite_short_version() {
  local version=$1
  if [[ $version =~ ^([0-9])([0-9]{2})([0-9]{2})[0-9]{2}$ ]]; then
    printf '%s.%s.%s' \
      "${BASH_REMATCH[1]}" \
      "${BASH_REMATCH[2]}" \
      "$((10#${BASH_REMATCH[3]}))"
    return 0
  fi
  return 1
}

vim_docdir() {
  local version=$1
  local major minor rest
  IFS=. read -r major minor rest <<<"$version"
  if [[ -z ${major:-} || -z ${minor:-} ]]; then
    return 1
  fi
  printf 'vim/vim%s%s' "$major" "$minor"
}

template_to_filename_regex() {
  local template=$1
  local filename=${template##*/}

  BASENAME_TEMPLATE=$filename perl -e '
    my $s = $ENV{BASENAME_TEMPLATE};
    $s =~ s/([.^\$|(){}\[\]\\+?*])/\\$1/g;
    $s =~ s/&[A-Za-z0-9._-]+;/[^\/"]+/g;
    print "^$s\$";
  '
}

parse_packages_html() {
  local html_file=$1
  local out_file=$2

  perl -0ne '
    while (m{
      <dt>\s*<span\b[^>]*class\s*=\s*"term"[^>]*>(.*?)\((.*?)\)\s*-\s*
      <span\b[^>]*class\s*=\s*"token"[^>]*>(.*?)</span>:\s*</span>\s*</dt>\s*
      <dd>(.*?)</dd>
    }sgx) {
      my ($term, $version, $size, $body) = ($1, $2, $3, $4);
      for ($term, $version, $size, $body) {
        s/\r//g;
      }

      $term    =~ s/<[^>]+>//g;
      $version =~ s/<[^>]+>//g;
      $size    =~ s/<[^>]+>//g;

      for ($term, $version, $size) {
        s/\s+/ /g;
        s/^\s+//;
        s/\s+$//;
      }

      my ($home) = $body =~ m{Home\ page:\s*<a\b[^>]*class\s*=\s*"ulink"[^>]*href\s*=\s*"([^"]+)"}s;
      my ($url)  = $body =~ m{Download:\s*<a\b[^>]*class\s*=\s*"ulink"[^>]*href\s*=\s*"([^"]+)"}s;
      my ($md5)  = $body =~ m{MD5\ sum:\s*<code\b[^>]*class\s*=\s*"literal"[^>]*>([0-9a-fA-F]+)</code>}s;

      next unless defined $url && defined $md5;
      $home = defined $home ? $home : q{__NO_HOME__};

      print join("\t", $term, $version, $size, $home, $url, lc $md5), "\n";
    }
  ' "$html_file" >"$out_file"
}

parse_patches_html() {
  local html_file=$1
  local out_file=$2

  perl -0ne '
    while (m{
      <dt>\s*<span\b[^>]*class\s*=\s*"term"[^>]*>(.*?)\s*-\s*
      <span\b[^>]*class\s*=\s*"token"[^>]*>(.*?)</span>:\s*</span>\s*</dt>\s*
      <dd>(.*?)</dd>
    }sgx) {
      my ($term, $size, $body) = ($1, $2, $3);
      for ($term, $size, $body) {
        s/\r//g;
      }

      $term =~ s/<[^>]+>//g;
      $size =~ s/<[^>]+>//g;

      for ($term, $size) {
        s/\s+/ /g;
        s/^\s+//;
        s/\s+$//;
      }

      my ($url) = $body =~ m{Download:\s*<a\b[^>]*class\s*=\s*"ulink"[^>]*href\s*=\s*"([^"]+)"}s;
      my ($md5) = $body =~ m{MD5\ sum:\s*<code\b[^>]*class\s*=\s*"literal"[^>]*>([0-9a-fA-F]+)</code>}s;

      next unless defined $url && defined $md5;

      print join("\t", $term, $size, $url, lc $md5), "\n";
    }
  ' "$html_file" >"$out_file"
}

append_update() {
  local updates_file=$1
  local entity_name=$2
  local entity_value=$3

  printf '%s\t%s\n' "$entity_name" "$entity_value" >>"$updates_file"
}

update_if_exists() {
  local updates_file=$1
  local entity_name=$2
  local entity_value=$3

  if [[ -n ${ENTITY_EXISTS[$entity_name]:-} ]]; then
    append_update "$updates_file" "$entity_name" "$entity_value"
  fi
}

load_package_template_metadata() {
  local line name value base

  while IFS= read -r line; do
    if [[ $line =~ ^\<\!ENTITY[[:space:]]+([^[:space:]]+)[[:space:]]+\"([^\"]*)\" ]]; then
      name=${BASH_REMATCH[1]}
      value=${BASH_REMATCH[2]}
      ENTITY_EXISTS["$name"]=1

      if [[ $name == *-url ]]; then
        base=${name%-url}
        PACKAGE_BASES+=("$base")
        PACKAGE_REGEX["$base"]="$(template_to_filename_regex "$value")"
      fi
    fi
  done <"$PACKAGES_TEMPLATE"
}

load_patch_template_metadata() {
  local line name value base

  while IFS= read -r line; do
    if [[ $line =~ ^\<\!ENTITY[[:space:]]+([^[:space:]]+)[[:space:]]+\"([^\"]*)\" ]]; then
      name=${BASH_REMATCH[1]}
      value=${BASH_REMATCH[2]}

      if [[ $name == *-patch && $name != *-patch-md5 && $name != *-patch-size ]]; then
        PATCH_BASES+=("$name")
        PATCH_TEMPLATE_VALUE["$name"]=$value
        PATCH_REGEX["$name"]="$(template_to_filename_regex "$value")"
      elif [[ $name == *-patch-md5 ]]; then
        base=${name%-md5}
        PATCH_TEMPLATE_MD5["$base"]=$value
      elif [[ $name == *-patch-size ]]; then
        base=${name%-size}
        PATCH_TEMPLATE_SIZE["$base"]=$value
      fi
    fi
  done <"$PATCHES_TEMPLATE"
}

find_matching_package_base() {
  local term=$1
  local filename=$2
  local base regex
  local fallback

  fallback=$(package_base_from_term "$term")
  if [[ -n ${ENTITY_EXISTS["${fallback}-size"]:-} || -n ${ENTITY_EXISTS["${fallback}-url"]:-} ]]; then
    printf '%s' "$fallback"
    return 0
  fi

  for base in "${PACKAGE_BASES[@]}"; do
    regex=${PACKAGE_REGEX[$base]}
    if [[ $filename =~ $regex ]]; then
      printf '%s' "$base"
      return 0
    fi
  done

  return 1
}

find_matching_patch_base() {
  local filename=$1
  local base regex

  for base in "${PATCH_BASES[@]}"; do
    regex=${PATCH_REGEX[$base]}
    if [[ $filename =~ $regex ]]; then
      printf '%s' "$base"
      return 0
    fi
  done

  return 1
}

apply_package_derivatives() {
  local updates_file=$1
  local base=$2
  local version=$3
  local download_url=$4
  local mm short sqlite_year perl_major perl_minor perl_patch

  case "$base" in
    automake)
      if mm=$(major_minor "$version"); then
        update_if_exists "$updates_file" "am-minor-version" "$mm"
      fi
      ;;
    expat)
      update_if_exists "$updates_file" "expat-dl-version" "${version//./_}"
      ;;
    linux)
      local linux_major linux_minor linux_patch
      IFS=. read -r linux_major linux_minor linux_patch <<<"$version"
      [[ -n ${linux_major:-} ]] && update_if_exists "$updates_file" "linux-major-version" "$linux_major"
      [[ -n ${linux_minor:-} ]] && update_if_exists "$updates_file" "linux-minor-version" "$linux_minor"
      [[ -n ${linux_patch:-} ]] && update_if_exists "$updates_file" "linux-patch-version" "$linux_patch"
      if [[ -n ${linux_major:-} && -n ${linux_minor:-} ]]; then
        update_if_exists "$updates_file" "linux-majmin-version" "${linux_major}.${linux_minor}"
      fi
      ;;
    ncurses)
      update_if_exists "$updates_file" "ncurses-base-version" "$version"
      ;;
    perl)
      IFS=. read -r perl_major perl_minor perl_patch <<<"$version"
      [[ -n ${perl_major:-} ]] && update_if_exists "$updates_file" "perl-version-major" "$perl_major"
      [[ -n ${perl_minor:-} ]] && update_if_exists "$updates_file" "perl-version-minor" "$perl_minor"
      [[ -n ${perl_patch:-} ]] && update_if_exists "$updates_file" "perl-version-patch" "$perl_patch"
      if [[ -n ${perl_major:-} && -n ${perl_minor:-} ]]; then
        update_if_exists "$updates_file" "perl-version-min" "${perl_major}.${perl_minor}"
      fi
      ;;
    python)
      if mm=$(major_minor "$version"); then
        update_if_exists "$updates_file" "python-minor" "$mm"
      fi
      ;;
    readline)
      if mm=$(major_minor "$version"); then
        update_if_exists "$updates_file" "readline-soversion" "$mm"
      fi
      ;;
    sqlite)
      if short=$(sqlite_short_version "$version"); then
        update_if_exists "$updates_file" "sqlite-short-version" "$short"
      fi
      if [[ $download_url =~ sqlite\.org/([0-9]{4})/ ]]; then
        sqlite_year=${BASH_REMATCH[1]}
        update_if_exists "$updates_file" "sqlite-year" "$sqlite_year"
      fi
      ;;
    tcl)
      if mm=$(major_minor "$version"); then
        update_if_exists "$updates_file" "tcl-major-version" "$mm"
      fi
      ;;
    util-linux)
      if mm=$(major_minor "$version"); then
        update_if_exists "$updates_file" "util-linux-minor" "$mm"
      fi
      ;;
    vim)
      if mm=$(vim_docdir "$version"); then
        update_if_exists "$updates_file" "vim-docdir" "$mm"
      fi
      ;;
  esac
}

build_package_updates() {
  local package_records_file=$1
  local updates_file=$2
  local term version size home download_url md5 filename base

  : >"$updates_file"

  while IFS=$'\t' read -r term version size home download_url md5; do
    [[ -n ${download_url:-} ]] || continue
    filename=${download_url##*/}

    if ! base=$(find_matching_package_base "$term" "$filename"); then
      warn "no package entity match for '$term' ($filename)"
      continue
    fi

    update_if_exists "$updates_file" "${base}-version" "$version"
    update_if_exists "$updates_file" "${base}-size" "$size"
    update_if_exists "$updates_file" "${base}-url" "$download_url"
    update_if_exists "$updates_file" "${base}-md5" "$md5"
    if [[ $home != "__NO_HOME__" ]]; then
      update_if_exists "$updates_file" "${base}-home" "$home"
    fi

    apply_package_derivatives "$updates_file" "$base" "$version" "$download_url"
  done <"$package_records_file"
}

render_updated_entity_file() {
  local template_file=$1
  local updates_file=$2
  local output_file=$3

  awk -v updates_file="$updates_file" '
    BEGIN {
      FS = "\t"
      while ((getline < updates_file) > 0) {
        updates[$1] = $2
      }
      close(updates_file)
    }

    {
      if (match($0, /^<!ENTITY[[:space:]]+([^[:space:]]+)/, fields)) {
        entity = fields[1]
        if (entity in updates) {
          line = $0
          sub(/"[^"]*"/, "\"" updates[entity] "\"", line)
          print line
          next
        }
      }

      print
    }
  ' "$template_file" >"$output_file"
}

build_patch_records() {
  local patch_records_file=$1
  local term size download_url md5 filename base

  while IFS=$'\t' read -r term size download_url md5; do
    [[ -n ${download_url:-} ]] || continue
    filename=${download_url##*/}

    if ! base=$(find_matching_patch_base "$filename"); then
      warn "no patch entity match for '$term' ($filename)"
      continue
    fi

    PATCH_ACTIVE["$base"]=1
    PATCH_VALUE["$base"]=$filename
    PATCH_MD5["$base"]=$md5
    PATCH_SIZE["$base"]=$size
  done <"$patch_records_file"
}

render_patch_entity_file() {
  local output_file=$1
  local base

  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '\n'
    printf '%s\n' '<!-- Start of Common Patches -->'
    printf '\n'

    for base in "${PATCH_BASES[@]}"; do
      if [[ -n ${PATCH_ACTIVE[$base]:-} ]]; then
        printf '<!ENTITY %s "%s">\n' "$base" "${PATCH_VALUE[$base]}"
        printf '<!ENTITY %s-md5 "%s">\n' "$base" "${PATCH_MD5[$base]}"
        printf '<!ENTITY %s-size "%s">\n' "$base" "${PATCH_SIZE[$base]}"
      else
        printf '<!-- <!ENTITY %s "%s"> -->\n' "$base" "${PATCH_TEMPLATE_VALUE[$base]}"
        printf '<!-- <!ENTITY %s-md5 "%s"> -->\n' "$base" "${PATCH_TEMPLATE_MD5[$base]}"
        printf '<!-- <!ENTITY %s-size "%s"> -->\n' "$base" "${PATCH_TEMPLATE_SIZE[$base]}"
      fi
      printf '\n'
    done
  } >"$output_file"
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PACKAGES_TEMPLATE="$SCRIPT_DIR/packages.ent"
PATCHES_TEMPLATE="$SCRIPT_DIR/patches.ent"

[[ -f $PACKAGES_TEMPLATE ]] || die "missing template file: $PACKAGES_TEMPLATE"
[[ -f $PATCHES_TEMPLATE ]] || die "missing template file: $PATCHES_TEMPLATE"

suffix=2
output_dir=$SCRIPT_DIR
version=
packages_html=
patches_html=

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suffix)
      [[ $# -ge 2 ]] || die "--suffix requires a value"
      suffix=$2
      shift 2
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || die "--output-dir requires a value"
      output_dir=$2
      shift 2
      ;;
    --packages-html)
      [[ $# -ge 2 ]] || die "--packages-html requires a value"
      packages_html=$2
      shift 2
      ;;
    --patches-html)
      [[ $# -ge 2 ]] || die "--patches-html requires a value"
      patches_html=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z $version ]]; then
        version=$1
        shift
      else
        die "unexpected argument: $1"
      fi
      ;;
  esac
done

if [[ -z $version && ( -z $packages_html || -z $patches_html ) ]]; then
  read -rp "MLFS version (example: 13.0-m32): " version
fi

[[ -n $version || ( -n $packages_html && -n $patches_html ) ]] || die "a version or both HTML input files are required"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

if [[ -z $packages_html ]]; then
  packages_html=$tmpdir/packages.html
  curl -fsSL "https://www.linuxfromscratch.org/mlfs/view/${version}/chapter03/packages.html" >"$packages_html"
fi

if [[ -z $patches_html ]]; then
  patches_html=$tmpdir/patches.html
  curl -fsSL "https://www.linuxfromscratch.org/mlfs/view/${version}/chapter03/patches.html" >"$patches_html"
fi

[[ -f $packages_html ]] || die "missing packages HTML: $packages_html"
[[ -f $patches_html ]] || die "missing patches HTML: $patches_html"

mkdir -p "$output_dir"

packages_records=$tmpdir/packages.tsv
patches_records=$tmpdir/patches.tsv
package_updates=$tmpdir/package-updates.tsv

declare -A ENTITY_EXISTS=()
declare -A PACKAGE_REGEX=()
declare -a PACKAGE_BASES=()

declare -A PATCH_REGEX=()
declare -A PATCH_TEMPLATE_VALUE=()
declare -A PATCH_TEMPLATE_MD5=()
declare -A PATCH_TEMPLATE_SIZE=()
declare -A PATCH_ACTIVE=()
declare -A PATCH_VALUE=()
declare -A PATCH_MD5=()
declare -A PATCH_SIZE=()
declare -a PATCH_BASES=()

load_package_template_metadata
load_patch_template_metadata

parse_packages_html "$packages_html" "$packages_records"
parse_patches_html "$patches_html" "$patches_records"
build_package_updates "$packages_records" "$package_updates"
build_patch_records "$patches_records"

packages_output="$output_dir/packages-${suffix}.ent"
patches_output="$output_dir/patches-${suffix}.ent"

render_updated_entity_file "$PACKAGES_TEMPLATE" "$package_updates" "$packages_output"
render_patch_entity_file "$patches_output"

printf 'Wrote %s\n' "$packages_output"
printf 'Wrote %s\n' "$patches_output"
