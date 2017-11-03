import os
import glob


def _read_and_compare(cache, ofs, f, size, tester):
    """Read a line from f at ofs, and test it.

    Finds out where the line starts, reads the line, calls tester with
    the line with newlines stripped, and returns the results.

    If ofs is in the middle of a line in f, then the following line will be
    used, otherwise the line starting at ofs will be used. (The term ``middle''
    includes the offset of the trailing '\\n'.)

    Bytes of f after offset `size' will be ignored. If a line spans over
    offset `size', it gets read fully (by f.readline()), and then truncated.

    If the line used starts at EOF (or at `size'), then tester won't be not
    called, and True is used instead.

    Args:
      cache: Currently ignored.
        TODO: Speed it up by adding caching of previous test results.
      ofs: The offset in f to read from. If ofs is in the middle of a line, then
        the following line will be used.
      f: Seekable file object or file-like object to read from. The methods
        f.tell(), f.seek(ofs_arg) and f.readline() will be used.
      size: Size limit for reading. Bytes in f after offset `size' will be
        ignored.
      tester: Single-argument callable which will be called for the line, with
        the trailing '\\n' stripped. If the line used is at EOF, then tester
        won't be called and True will be used as the result.
    Returns:
      List or tuple of the form [fofs, g, dummy], where g is the test result
      (or True at EOF), fofs is the start offset of the line used in f,
      and dummy is an implementation detail that can be ignored.
    """
    assert 0 <= ofs <= size
    if ofs:
        if f.tell() != ofs - 1:  # Avoid lseek(2) call if not needed.
            f.seek(ofs - 1)  # Just to figure out where our line starts.
        f.readline()  # Ignore previous line, find our line.
        fofs = min(size, f.tell())
    else:
        fofs = 0
        if size and f.tell():  # Avoid lseek(2) call if not needed.
            f.seek(0)
    assert 0 <= ofs <= fofs <= size
    g = True  # EOF is always larger than any line we search for.
    if fofs < size:
        line = f.readline()  # We read at f.tell() == fofs.
        if f.tell() > size:
            line = line[:size - fofs]
        if line:
            g = tester(line.rstrip('\n'))
    return fofs, g, ()


def bisect_way(f, x, is_left, size=None):
    """Return an offset where to insert line x into sorted file f.

    Bisection (binary search) on newline-separated, sorted file lines.
    If you use sort(1) to sort the file, run it as `LC_ALL=C sort' to make it
    lexicographically sorted, ignoring locale.

    If there is no trailing newline at the end of f, and the returned offset is
    at the end of f, then don't forget to append a '\\n' before appending x.

    Args:
      f: Seekable file object or file-like object to search in. The methods
        f.tell(), f.seek(ofs_arg) and f.readline() will be used.
      x: Line to search for. Must not contain '\\n', except for maybe a
        trailing one, which will be ignored if present.
      is_left: If true, emulate bisect_left. See the return value for more info.
      size: Size limit for reading. Bytes in f after offset `size' will be
        ignored. If None, then no limit.
    Returns:
      Byte offset in where where to insert line x. If is_left is true (i.e.
      bisect_left), then the smallest possible offset is returned, otherwise
      (i.e. bisect_right) the largest possible address is returned.
    """
    x = x.rstrip('\n')
    if is_left and not x:  # Shortcut.
        return 0
    if size is None:
        f.seek(0, 2)  # Seek to EOF.
        size = f.tell()
    if size <= 0:  # Shortcut.
        return 0
    if is_left:
        tester = x.__le__  # x <= y.
    else:
        tester = x.__lt__  # x < y.
    lo, hi, mid, cache = 0, size - 1, 1, []
    while lo < hi:
        mid = (lo + hi) >> 1
        midf, g, _ = _read_and_compare(cache, mid, f, size, tester)
        if g:
            hi = mid
        else:
            lo = mid + 1
    if mid != lo:
        midf = _read_and_compare(cache, lo, f, size, tester)[0]
    return midf


def bisect_right(f, x, size=None):
    """Return the largest offset where to insert line x into sorted file f.

    Similar to bisect.bisect_right, but operates on lines rather then elements.
    Convenience function which just calls bisect_way(..., is_left=False).
    """
    return bisect_way(f, x, False, size)


def bisect_left(f, x, size=None):
    """Return the smallest offset where to insert line x into sorted file f.

    Similar to bisect.bisect_left, but operates on lines rather then elements.
    Convenience function which just calls bisect_way(..., is_left=True).
    """
    return bisect_way(f, x, True, size)


def bisect_interval(f, x, y=None, is_open=False, size=None):
    """Return (start, end) offset pair for lines between x and y.

    Args:
      f: Seekable file object or file-like object to search in. The methods
        f.tell(), f.seek(ofs_arg) and f.readline() will be used.
      x: First line to search for. Must not contain '\\n', except for maybe a
        trailing one, which will be ignored if present.
      y: First line to search for. Must not contain '\\n', except for maybe a
        trailing one, which will be ignored if present. If None, x is used.
      is_open: If true, then the returned interval consists of lines
        x <= line < y. Otherwise it consists of lines x <= line <= y.
      size: Size limit for reading. Bytes in f after offset `size' will be
        ignored. If None, then no limit.
    Returns:
      Return (start, end) offset pair containing lines between x and y (see
      arg is_open whether x and y are inclusive) in sorted file f, before offset
      `size'. These offsets contain the lines: start <= ofs < end. Trailing
      '\\n's are included in the interval (except at EOF if there was none).
    """
    x = x.rstrip('\n')
    if y is None:
        y = x
    else:
        y = y.strip('\n')
    end = bisect_way(f, y, is_open, size)
    if is_open and x == y:
        return end, end
    else:
        return bisect_way(f, x, True, end), end


class NewFile(file):
    def __init__(self, name, start_date):
        super(NewFile, self).__init__(name, "rb")
        start_date = start_date
        start_lineno, _ = bisect_interval(open(self.name, "rb"),
                                          start_date)

        # if EOF, reading from the beginning line
        self.seek(-1, os.SEEK_END)
        if start_lineno >= self.tell():
            self.seek(0, 0)
            self.found = False
        else:
            self.seek(start_lineno)
            self.found = True


def find_file(filename, file_folder, depth=None):
    matching_filepaths = list()
    if depth == 0:
        return matching_filepaths

    relative_depth = 1
    if depth is not None:
        relative_depth = depth

    # current dir
    # matching_filepaths.extend(glob.glob(os.path.join(file_folder, filename)))
    files = glob.glob(os.path.join(file_folder, filename))
    for file in files:
        # only return dir name
        file_dir = os.path.dirname(file)
        if file_dir not in matching_filepaths:
            matching_filepaths.append(file_dir)

    if depth is None or relative_depth > 0:
        for dir in os.listdir(file_folder):
            next_dir = os.path.join(file_folder, dir)
            if os.path.isdir(next_dir):
                temp_depth = relative_depth - 1
                if depth is None:
                    temp_depth = None
                matching_filepaths.extend(find_file(filename,
                                                    next_dir,
                                                    temp_depth))

    return matching_filepaths
