#!/bin/sh

echo "WARNING: this tool is not ready" > /dev/stderr
exit 1 

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

function fix_dylib_dep() {
  local install_dir="$1"
  local dylib="$2"
  local dep="$3"
  local rn="$(rel ${install_dir} ${dylib})"
  
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
    #D "'$(basename $d)' = '$(basename $dep)'?"
    if [ "$(basename $d)" = "$(basename $dep)" ]; then
      D dylib: ${rn} dep: "@loader_path/"$(rel ${install_dir} ${dep})
      #install_name_tool -change ${dep} @loader_path/${rn} ${dylib} 
      return
    fi
  done
 
  die "unhandled dylib: $(basename ${dylib}) dep: ${dep}"
}

function fix_dylib_id() {
  local install_dir="$1"
  local dylib="$2"
  local id="$(dylib_id ${dylib})"
  local rn="$(rel ${install_dir} ${dylib})"
  
  if [[ $id == "/System/Library/Frameworks/"*  ]]; then
    #D "skipping $(basename ${dylib}) with id ${id}"
    return
  fi
      
  D dylib: ${rn} id: "@loader_path/${rn}"
  #install_name_tool -change ${dep} @loader_path/${rn} ${dylib} 
}

function make_portable_dylib() {
  local install_dir="$1"
  local dylib="$2"
  local id=""
  local rn="${dylib/${install_dir}\//}"
  local bn="$(basename $1)"
  local dn="$(dirname $1)"
  local dep=""
  
  #D "Processing ${dylib}"
  
  local lineno=0
  tmpfile="$(mktemp /tmp/$(basename ${0}).XXXXXXXX)" \
    || die failed to create tmpfile
    
  #D "using tmpfile ${tmpfile}"
    
#  exec 3<>"${tmpfile}" \
#    || die failed to open ${tmpfile} as fd 3
#    
#  D "opened ${tmpfile} as fd 3"
        
  otool -L ${dylib} > ${tmpfile} \
    || die failed to write otool output to ${tmpfile}
    
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

function main() {
  
  local install_dir="$(echo $1 | sed -e 's|//|/|g' -e 's|/$||')"
  DYLIBS="$(find_dylibs ${install_dir})"
  DYLIBS=($DYLIBS)
  
  for i in ${DYLIBS[*]}; do
    IDS+=" $(dylib_id ${i})"
  done
  IDS=($IDS)
  
#  echo DYLIBS: ${DYLIBS[*]}
#  echo IDS: ${IDS[*]}
  
  for i in ${DYLIBS[*]}; do
    make_portable_dylib $install_dir $i
  done
}

#main @INSTALL_DIR@/
main /Applications/GNURadio.app/Contents/MacOS