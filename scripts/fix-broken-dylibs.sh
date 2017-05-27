#!/bin/sh

DEBUG=1

DYLIB_EXTS="dylib so"

DYLIBS=""
IDS=""

function die() {
  local r=$?
  if [ 0 -eq $r ]; then
    r=1
  fi
  echo "E: ${FUNCNAME[1]}():${BASH_LINENO[1]}: $@"
  exit $r
}

function D() {
  if [ "" != "${DEBUG}" ]; then
    echo "D: ${FUNCNAME[1]}():${BASH_LINENO[0]}: $@"
  fi
}

function rel() {
  local install_dir="$1"
  local fn="$2"
  echo ${fn} | sed -e "s|$1/||g" 
}

function find_dylibs() {
  local d="$1"
  local n=""
  
#  for e in $DYLIB_EXTS; do
#    [[ ! -z "${n}" ]] && n+=" -o"
#    n+=" -name '*.${e}'"
#  done

  find ${d} -type f -name '*.dylib' -o -name '*.so' | sort -u
}

function dylib_id() {
  local dylib="$1"
  local id="$(otool -L $1  | head -n 2 | tail -n 1 | awk '{print $1}')"
  echo "${id}"
}

function check_file_exists_relative_to() {
  local rfile="$1"
  local rdir="$2"
  local r
  cd ${rdir} && test -e ../${rn}
  r=$?
  cd $OLDPWD
  return $r
}

function change_dylib_dep() {
  local from="$1"
  local to="$2"
  local dylib="$3"
  D install_name_tool -change ${from}  ${to} ${dylib}
  install_name_tool -change ${from}  ${to} ${dylib} \
    || die "command failed: install_name_tool -change ${from}  ${to} ${dylib}"
}

function change_dylib_id() {
  local dylib="$1"
  local id="$2"
  install_name_tool -id ${id} ${dylib} \
    || die "command failed: install_name_tool -id ${id} ${dylib}"
}

function fix_dylib_dep() {
  local install_dir="$1"
  local dylib="$2"
  local dep="$3"
  local rn
  
  if [[ $dep == "@rpath"*  ]]; then
    #D "$(basename ${dylib}): skipping dep ${dep}"
    return
  fi
  if [[ $dep == "/usr/"*  ]]; then
    #D "$(basename ${dylib}): skipping dep ${dep}"
    return
  fi
  if [[ $dep == "/opt/"*  ]]; then
    #D "$(basename ${dylib}): skipping dep ${dep}"
    return
  fi
    if [[ $dep == "/System/Library/Frameworks/"*  ]]; then
    #D "$(basename ${dylib}): skipping dep ${dep}"
    return
  fi

  for d in ${IDS[*]} ${DYLIBS[*]}; do
    if [ "$(basename $d)" = "$(basename $dep)" ]; then
      if [[ $d == "@rpath/../"* ]]; then
        rn="${d/@rpath\/..\//}"
      else
        rn="$(rel ${install_dir}/usr ${dep})"
      fi
      check_file_exists_relative_to ../${rn} ${install_dir}/usr/bin \
        || die "@rpath/../${rn}: No such file or directory"
      change_dylib_dep "${dep}" "@rpath/../${rn}" "${dylib}" 
      return
    fi
  done
 
  die "unhandled dylib: $(basename ${dylib}) dep: ${dep}"
}

function fix_dylib_id() {
  local install_dir="$1"
  local dylib="$2"
  local id="$(dylib_id ${dylib})"
  local rn
  
  if [[ $id == "@rpath"*  ]]; then
    #D "$(basename ${dylib}): skipping dep ${dep}"
    return
  fi
  
  if [[ $id == "/usr/"*  ]]; then
    #D "$(basename ${dylib}): skipping dep ${dep}"
    return
  fi
  
  if [[ $id == "/System/Library/Frameworks/"*  ]]; then
    #D "skipping $(basename ${dylib}) with id ${id}"
    return
  fi

  if [[ $id == *"/"* ]]; then
    rn="$(rel ${install_dir}/usr ${id})"
  else
    rn="$(rel ${install_dir}/usr ${dylib})"
  fi

  check_file_exists_relative_to ../${rn} ${install_dir}/usr/bin \
      || die "@rpath/../${rn}: No such file or directory"
  change_dylib_id ${dylib} @rpath/../${rn}
}

function make_portable_dylib() {
  local install_dir="$1"
  local dylib="$2"
  local id=""
  local rn="${dylib/${install_dir}\//}"
  local bn="$(basename $1)"
  local dn="$(dirname $1)"
  local dep=""
  local line
  
  D "Processing ${dylib}"
  
  local lineno=0
  tmpfile="$(mktemp /tmp/$(basename FOO).XXXXXXXX)" \
    || die failed to create tmpfile
    
  #D "using tmpfile ${tmpfile}"
    
#  exec 3<>"${tmpfile}" \
#    || die failed to open ${tmpfile} as fd 3
#    
#  D "opened ${tmpfile} as fd 3"
        
  otool -L ${dylib} > ${tmpfile} \
    || die "failed command: otool -L ${dylib} > ${tmpfile}"
    
  #D "wrote otool output to ${tmpfile}"
    
  while read -r line; do
    lineno=$((lineno+1))
    if [ 1 -eq $lineno ]; then
      continue
    fi
    if [ 2 -eq $lineno ]; then
      fix_dylib_id ${install_dir} ${dylib}
      continue
    fi
    dep="$(echo $line | awk '{print $1}')"
    fix_dylib_dep ${install_dir} ${dylib} ${dep}
  done < ${tmpfile}

  rm -f ${tmpfile} \
    || die failed to remove ${tmpfile}        
  #D "removed ${tmpfile}"
}

function progress() {
  local num="$1"
  local den="$2"
  local pcnt=$(( (num+1) * 100 / den ))
  # a decent way to get actual terminal width?
  local twidth=80
  local front=6
  local back=1
  local prog=$(((twidth-front-back) * pcnt / 100))
  local i
  printf "\r%3d%% " ${pcnt}; /bin/echo -n "|"
  for ((i=0; i < prog; i++)); do
    printf "="
  done
  for ((i=0; i < twidth - front - back - prog; i++)); do
    printf "-"
  done
  /bin/echo "|"
}

function scanlibs() {

  local install_dir="$(echo $1 | sed -e 's|//|/|g' -e 's|/$||')"
  DYLIBS="$(find_dylibs ${install_dir})"
  DYLIBS=($DYLIBS)
  
  for i in ${DYLIBS[*]}; do
    IDS+=" $(dylib_id ${i})"
  done
  IDS=($IDS)
  
#  echo DYLIBS: ${DYLIBS[*]}
#  echo IDS: ${IDS[*]}
}

function main() {
  local install_dir="$1"
  scanlibs "${install_dir}"
  
  j=0
  for i in ${DYLIBS[*]}; do
    progress $j ${#DYLIBS[@]}
    j=$((j+1))
    make_portable_dylib "$install_dir" "$i"
  done
  echo ""
}

INSTALL_DIR="${INSTALL_DIR:-/Applications/GNURadio.app/Contents/MacOS}"
main "${INSTALL_DIR}"
