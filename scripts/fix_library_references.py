#!/usr/bin/env python
# -*- coding: utf-8 -*-
# vim:set ft=python ai ts=8 et sw=4 sts=4 nowrap:
# The above line sets vim to set tab stops at 4 columns, and fill them with spaces instead of tab characters.

"""
fix_library_references.py - Rewrite library references to use @loader_path
"""

import os as _os, stat as _stat, subprocess as _subprocess

def run_otool(filename, get_refs=False):
    otool_opt = '-L' if get_refs else '-D'
    p = _subprocess.Popen(['otool', otool_opt, filename], stdout=_subprocess.PIPE, stderr=_subprocess.PIPE)
    stdoutdata, stderrdata = p.communicate()
    if p.returncode!=0:
        return [] if get_refs else None
    if len(stderrdata)!=0:
        _sys.stderr.write('otool {} {!r} stderr={!r}\n'.format(otool_opt, filename, stderrdata))
    lines = stdoutdata.splitlines()
    if len(lines)==0:
        return [] if get_refs else None
    # The first line always looks like:
    if lines[0]!=filename+':':
        raise ValueError('Unexpected first line from "otool {}" does not match: {!r}\nExpected is {!r}'.format(otool_opt, lines[0], filename+':'))
    del lines[0]
    if len(lines)==0:
        return [] if get_refs else None
    if not get_refs:
        # Parsing otool output for -D is easy:
        # zero(ttys001):...orts/scripts> otool -D ~/Applications/GNURadio.app/Contents/MacOS/usr/lib/libqwt.6.dylib    
        #/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libqwt.6.dylib:
        #/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libqwt.6.dylib
        if len(lines)!=1:
            _sys.stderr.write('Warning: otool {} {!r} returned more than 1 id??? --> {!r}\n'.format(otool_opt, filename, lines))
        return lines[0]
    #else:
    # Parsing otool output for -L is annoying:
    #zero(ttys001):...orts/scripts> otool -L ~/Applications/GNURadio.app/Contents/MacOS/usr/lib/libqwt.6.dylib
    #/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libqwt.6.dylib:
    #	/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libqwt.6.dylib (compatibility version 6.1.0, current version 6.1.3)
    #	/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libQtSvg.4.dylib (compatibility version 4.4.0, current version 4.4.3)
    #	/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libQtOpenGL.4.dylib (compatibility version 4.4.0, current version 4.4.3)
    #	/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libQtGui.4.dylib (compatibility version 4.4.0, current version 4.4.3)
    #	/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libpng16.16.dylib (compatibility version 45.0.0, current version 45.0.0)
    #	/opt/X11/lib/libSM.6.dylib (compatibility version 7.0.0, current version 7.1.0)
    #	/opt/X11/lib/libICE.6.dylib (compatibility version 10.0.0, current version 10.0.0)
    #	/opt/X11/lib/libXi.6.dylib (compatibility version 8.0.0, current version 8.0.0)
    #	/opt/X11/lib/libXrender.1.dylib (compatibility version 5.0.0, current version 5.0.0)
    #	/opt/X11/lib/libXrandr.2.dylib (compatibility version 5.0.0, current version 5.0.0)
    #	/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libfreetype.6.dylib (compatibility version 19.0.0, current version 19.6.0)
    #	/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libfontconfig.1.dylib (compatibility version 11.0.0, current version 11.2.0)
    #	/opt/X11/lib/libXext.6.dylib (compatibility version 11.0.0, current version 11.0.0)
    #	/opt/X11/lib/libX11.6.dylib (compatibility version 10.0.0, current version 10.0.0)
    #	/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libQtCore.4.dylib (compatibility version 4.4.0, current version 4.4.3)
    #	/usr/lib/libiconv.2.dylib (compatibility version 7.0.0, current version 7.0.0)
    #	/usr/lib/libresolv.9.dylib (compatibility version 1.0.0, current version 1.0.0)
    #	/usr/lib/libz.1.dylib (compatibility version 1.0.0, current version 1.2.8)
    #	/usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1238.60.2)
    #	/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libgthread-2.0.dylib (compatibility version 5102.0.0, current version 5102.0.0)
    #	/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libglib-2.0.dylib (compatibility version 5102.0.0, current version 5102.0.0)
    #	/Users/dholl/Applications/GNURadio.app/Contents/MacOS/usr/lib/libintl.9.dylib (compatibility version 11.0.0, current version 11.4.0)
    #	/opt/X11/lib/libGLU.1.dylib (compatibility version 5.0.0, current version 5.1.0)
    #	/opt/X11/lib/libGL.1.dylib (compatibility version 4.0.0, current version 4.0.0)
    #	/usr/lib/libc++.1.dylib (compatibility version 1.0.0, current version 307.5.0)
    lines = [l.strip() for l in lines]
    # Now get rid of this stuff from end of each line: " (compatibility version 6.1.0, current version 6.1.3)"
    for line_ndx in range(len(lines)):
        l = lines[line_ndx]
        if l[-1]!=')':
            _sys.stderr.write('Warning: otool {} {!r} line does not end with ")": {!r}\n'.format(otool_opt, filename, l))
            continue
        ndx = l.rfind(' (')
        if ndx==-1:
            _sys.stderr.write('Warning: otool {} {!r} line ends with ")" but does not contain " (": {!r}\n'.format(otool_opt, filename, l))
            continue
        lines[line_ndx] = l[:ndx]
    return lines

def get_library_refs(filename):
    return run_otool(filename, get_refs=True)

def get_library_id(filename):
    return run_otool(filename, get_refs=False)

def install_name_tool(filepath, new_lib_id=None, change_refs=[], change_rpaths=[], add_rpaths=[], delete_rpaths=[]):
    """install_name_tool - change dynamic shared library install names
    filepath: string
    new_lib_id: string
    change_refs: iterable of tuple of 2 strings per tuple
    change_rpaths: iterable of tuple of 2 strings per tuple
    add_rpaths: iterable of strings
    delete_rpaths: iterable of strings
    """

    args = []
    if new_lib_id:
        args += ['-id', new_lib_id]
    for old, new in change_refs:
        args += ['-change', old, new]
    for old, new in change_rpaths:
        args += ['-rpath', old, new]
    for new in add_rpaths:
        args += ['-add_rpath', new]
    for old in delete_rpaths:
        args += ['-delete_rpath', old]
    if len(args)==0:
        # Nothing to do.
        return
    args = ['install_name_tool'] + args + [filepath]
    p = _subprocess.Popen(args, stdout=_subprocess.PIPE, stderr=_subprocess.PIPE)
    stdoutdata, stderrdata = p.communicate()
    if p.returncode!=0 or len(stdoutdata)!=0 or len(stderrdata)!=0:
        _sys.stderr.write('cmd={!r}\n'.format(args))
        _sys.stderr.write('\tstatus={}\n'.format(p.returncode))
        _sys.stderr.write('\tstdout={!r}\n'.format(stdoutdata))
        _sys.stderr.write('\tstderr={!r}\n'.format(stderrdata))
    if p.returncode!=0:
        raise RuntimeError('{!r} exited with status {}'.format(args, p.returncode))

def norm_split_path(path):
    """
    '../..//some/.///path//' -> ['..', '..', 'some', 'path']
    '////../..//some/.///path//' -> ['', 'some', 'path']
    """
    #@rpath
    #@loader_path
    #@executable_path
    return _os.path.normpath(path).split(_os.sep)

def path_is_subpath(basepath, filepath):
    norm_basepath = norm_split_path(basepath)
    norm_filepath = norm_split_path(filepath)
    return len(norm_filepath)>=len(norm_basepath) and norm_basepath==norm_filepath[:len(norm_basepath)]

def count_leading_matches(norm_path1, norm_path2):
    count = 0
    for a, b in zip(norm_path1, norm_path2):
        if a!=b:
            break
        count += 1
    return count

def path_join(*path_parts):
    return '/'.join(path_parts)

def translate_library_path(filepath, lib_ref):
    """translate_library_path - return new_lib_ref using @loader_path relative to filepath"""
    # Normalize paths:
    norm_filepath = norm_split_path(filepath)
    norm_lib_ref = norm_split_path(lib_ref)
    if norm_lib_ref[0]=='@loader_path':
        norm_working_lib_ref = norm_filepath[:-1] + norm_lib_ref[1:]
        norm_working_lib_ref = norm_split_path(path_join(*norm_working_lib_ref))
    elif norm_lib_ref[0]=='@executable_path':
        if not (mode & executable) or norm_filepath[-1].endswith(('.dylib', '.so')):
            _sys.stderr.write('Found @executable_path in lib_ref={!r} during basepath={!r}.  Will handle this as @loader_path\n'.format(lib_ref, basepath))
        norm_working_lib_ref = norm_filepath[:-1] + norm_lib_ref[1:]
        norm_working_lib_ref = norm_split_path(path_join(*norm_working_lib_ref))
    elif norm_lib_ref[0]=='@rpath':
        _sys.stderr.write('Found @rpath in lib_ref={!r} during basepath={!r}\n'.format(lib_ref, basepath))
        norm_working_lib_ref = norm_lib_ref
    else:
        norm_working_lib_ref = norm_lib_ref
    if not _os.path.isfile(path_join(*norm_working_lib_ref)):
        _sys.stderr.write('*** Did not find file {!r} for lib_ref={!r} during basepath={!r}.  norm_working_lib_ref={!r}\n'.format(path_join(*norm_working_lib_ref), lib_ref, basepath, norm_working_lib_ref))
    # Given inputs such as:
    #   norm_filepath = [ '', 'Users', 'dholl', 'Applications', 'GNURadio.app', 'Contents', 'MacOS', 'usr', 'lib', 'bob' , 'jack'                , 'libqwt.6.dylib' ]
    #   norm_lib_ref  = [ '', 'Users', 'dholl', 'Applications', 'GNURadio.app', 'Contents', 'MacOS', 'usr', 'lib', 'jill', 'libQtOpenGL.4.dylib'                    ]
    num_common_prefix = count_leading_matches(norm_filepath, norm_lib_ref)
    #   num_common_prefix = 9
    f = norm_filepath[num_common_prefix:]
    r = norm_working_lib_ref[num_common_prefix:]
    if len(f)<1:
        raise ValueError('len(f)<1  f={!r}'.format(f))
    if len(r)<1:
        raise ValueError('len(r)<1  r={!r}'.format(r))
    #   f = [ 'bob' , 'jack'               , 'libqwt.6.dylib' ]
    #   r = [ 'jill', 'libQtOpenGL.4.dylib'                   ]
    # Now, since f still has 2 leading entries, 'bob', and 'jack', we'll need to insert two sets of '..' before r.
    num_dotdots = len(f)-1
    new_norm_lib_ref = ['@loader_path'] + ['..'] * num_dotdots + r
    new_lib_ref = path_join(*new_norm_lib_ref)
    return new_lib_ref

def process_file(basepath, filepath, mode, verbose=0):
    lib_refs = get_library_refs(filepath)
    lib_id = get_library_id(filepath)
    if len(lib_refs)>0 and lib_refs[0]==lib_id:
        # get_library_refs relies on otool which includes the library id (if
        # present) at the start of the list of references.  Filter it out:
        del lib_refs[0]
    if len(lib_refs)==0 and (lib_id is None):
        return

    wrote_header = False

    if verbose>=2:
        _sys.stdout.write('{!r}\n'.format(filepath))
        wrote_header = True

    #_sys.stdout.write('File: {!r}\nBase: {!r}\n'.format(filepath, basepath))
    #if lib_id:
    #    _sys.stdout.write('\tID: {!r}\n'.format(lib_id))
    #if lib_refs:
    #    _sys.stdout.write('\tReferences:\n\t\t{}\n'.format('\n\t\t'.join([repr(s) for s in lib_refs])))
    #if lib_id is not None:
    #    if filepath!=lib_id:
    #        _sys.stderr.write('ID of {!r} is {!r}\n'.format(filepath, lib_id))
    # Raise error if filepath is not under basepath:
    if not path_is_subpath(basepath, filepath):
        raise ValueError('filepath is not under basebath.  filepath={!r}  basepath={!r}'.format(filepath, basepath))

    # Only consider lib_refs that are under basepath:
    #_sys.stderr.write('Unfiltered lib_refs = {!r}\n'.format(lib_refs))
    lib_refs = filter(lambda lib_ref: path_is_subpath(basepath, lib_ref), lib_refs)
    #_sys.stderr.write('Filtered lib_refs = {!r}\n'.format(lib_refs))

    # Start taking notes of what changes we'd like to make:
    new_lib_id = None # None indicate Don't change it 
    change_refs = [] # a list of (oldref, newref) tuples

    assert len(_os.sep)==1
    if lib_id:
        tmp_lib_id = lib_id.rsplit(_os.sep, 1)[-1]
        if lib_id != tmp_lib_id:
            new_lib_id = tmp_lib_id
            if verbose>=1:
                if not wrote_header:
                    _sys.stdout.write('{!r}\n'.format(filepath))
                    wrote_header = True
                _sys.stdout.write('\tid: {!r} -> {!r}\n'.format(lib_id, new_lib_id))
        del tmp_lib_id
    # Compare list in lib_refs with filepath:
    for lib_ref in lib_refs:
        new_lib_ref = translate_library_path(filepath, lib_ref)
        if new_lib_ref!=lib_ref:
            if verbose>=1:
                if not wrote_header:
                    _sys.stdout.write('{!r}\n'.format(filepath))
                    wrote_header = True
                _sys.stdout.write('\tref: {!r} -> {!r}\n'.format(lib_ref, new_lib_ref))
            change_refs.append((lib_ref, new_lib_ref))

    install_name_tool(filepath, new_lib_id=new_lib_id, change_refs=change_refs)

# walktree is based on example in https://docs.python.org/2/library/stat.html
def walktree(top_path, callback):
    executable = _stat.S_IEXEC | _stat.S_IXGRP | _stat.S_IXOTH
    # https://docs.python.org/3/library/os.html#os.scandir
    # _os.scandir from Python 3 would be better.
    for f in _os.listdir(top_path):
        pathname = _os.path.join(top_path, f)
        mode = _os.lstat(pathname).st_mode
        if _stat.S_ISLNK(mode):
            # Skip symbolic links
            continue
        if _stat.S_ISDIR(mode):
            walktree(pathname, callback)
            continue
        if _stat.S_ISREG(mode):
            # Search all executable files (though they may be shell scripts) as well as *.dylib and *.so
            if (mode & executable) or pathname.endswith(('.dylib', '.so')):
                callback(pathname, mode=mode)
            continue

if __name__ == "__main__":
    import sys as _sys
    if len(_sys.argv)<2:
        _sys.stderr.write('Usage: {} [-v] [-v] path\n\t-v - Increase verbose reporting level\n\t\tDefault is only print warning and errors.\n\t\tSingle -v prints changed library references\n\t\tTwo -v -v also prints upon finding any file with a library id or references'.format(_sys.argv[0]))

    verbose = 0

    # Undocumented feature:  If the user happens to specify multiple paths, then we'll handle each separately:
    for basepath in _sys.argv[1:]:
        if basepath == '-v':
            # This is a command line arg to enable verbose reporting.
            verbose += 1
            continue
        walktree(basepath, lambda filepath, mode: process_file(basepath, filepath, mode, verbose))
