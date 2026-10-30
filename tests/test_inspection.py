import struct
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from workspace import checked_sections, va_offset, inventory, differences

def package():
    names=['None','Core','Package','Class','Thing']
    namebytes=b''.join(struct.pack('<i',len(n)+1)+n.encode()+b'\0'+struct.pack('<I',0) for n in names)
    no=64;io=no+len(namebytes);imports=struct.pack('<iihi',1,2,0,1)
    eo=io+len(imports);payload_off=eo+26
    # Class=-1 stored zero-extended in 32-bit field, then interpreted as signed16.
    exports=struct.pack('<iihiIii',65535,0,0,4,0,1,payload_off)
    header=struct.pack('<9I',0x9e2a83c1,151,1,len(names),no,1,eo,1,io)+bytes(16)+struct.pack('<iii',1,1,len(names))
    return bytearray(header+namebytes+imports+exports+b'X')


def xbe():
    b=bytearray(0x220);b[:4]=b'XBEH'
    for off,val in {0x104:0x10000,0x108:0x200,0x10c:0x1020,0x11c:1,0x120:0x10180}.items():struct.pack_into('<I',b,off,val)
    struct.pack_into('<6I',b,0x180,6,0x11000,0x20,0x200,0x10,0x101c0);b[0x1c0:0x1c6]=b'.text\0'
    return b

from uc2_package import inspect, FormatError, signed16

class PackageTests(unittest.TestCase):
    def test_valid_tables_and_short_cast(self):
        d=inspect(package());self.assertEqual(d['exports'][0]['class'],-1);self.assertEqual(d['package_imports'],['Core'])
        self.assertEqual(signed16(0xffff),-1)
    def test_licensee_one(self):
        b=package();struct.pack_into('<I',b,4,0x10097);self.assertEqual(inspect(b)['licensee_version'],1)
    def test_short_payload(self):
        with self.assertRaises(FormatError):inspect(package()[:-1])
    def test_invalid_table_extent(self):
        b=package();struct.pack_into('<I',b,24,len(b)+1)
        with self.assertRaises(FormatError):inspect(b)
    def test_invalid_name(self):
        b=package();eo=struct.unpack_from('<I',b,24)[0];struct.pack_into('<i',b,eo+10,999)
        with self.assertRaises(FormatError):inspect(b)
    def test_outer_cycle(self):
        b=package();eo=struct.unpack_from('<I',b,24)[0];struct.pack_into('<h',b,eo+8,1)
        with self.assertRaisesRegex(FormatError,'cycle'):inspect(b)
    def test_negative_count(self):
        b=package();struct.pack_into('<i',b,12,-1)
        with self.assertRaises(FormatError):inspect(b)
    def test_unknown_version(self):
        b=package();struct.pack_into('<I',b,4,125)
        with self.assertRaises(FormatError):inspect(b)
    def test_table_overlap(self):
        b=package();struct.pack_into('<I',b,32,64)
        with self.assertRaises(FormatError):inspect(b)

class XbeTests(unittest.TestCase):
    def test_mapping_and_zero_fill(self):
        secs=checked_sections(xbe());self.assertEqual(va_offset(secs,0x11004,4),0x204)
        with self.assertRaises(ValueError):va_offset(secs,0x11010)
        with self.assertRaises(ValueError):va_offset(secs,0x1100f,2)
    def test_truncated_xbe(self):
        with self.assertRaises(ValueError):checked_sections(xbe()[:100])
    def test_section_overrun(self):
        b=xbe();struct.pack_into('<I',b,0x190,0x1000)
        with self.assertRaises(ValueError):checked_sections(b)

class ManifestTests(unittest.TestCase):
    def test_changes_missing_and_added(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);(p/'a').write_bytes(b'a');(p/'b').write_bytes(b'b');old=inventory(p)
            (p/'a').write_bytes(b'z');(p/'b').unlink();(p/'c').write_bytes(b'c')
            self.assertEqual(differences(old,inventory(p)),{'missing':['b'],'added':['c'],'changed':['a']})
    def test_case_collision(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);(p/'A').write_bytes(b'a');(p/'a').write_bytes(b'b')
            self.assertEqual(len(inventory(p)['case_collisions']),1)
    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d);(p/'a').symlink_to('/nonexistent')
            with self.assertRaises(ValueError):inventory(p)


if __name__=='__main__':unittest.main()
