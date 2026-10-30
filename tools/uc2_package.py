"""Bounded metadata reader for the observed UC2 UE2X v151/0 packages.

Layout references (not copied source): UEViewer UnPackage.cpp Import::Serialize,
UnPackage2.cpp Export::Serialize2X. No object payload or bytecode decoding.
"""
import struct
from collections import Counter

class FormatError(ValueError):
    pass

class Reader:
    def __init__(self, data, offset=0):
        self.data, self.pos = data, offset

    def take(self, size):
        if size < 0 or self.pos < 0 or self.pos + size > len(self.data):
            raise FormatError(f'out-of-bounds read: offset={self.pos}, size={size}')
        result = self.data[self.pos:self.pos + size]
        self.pos += size
        return result

    def unpack(self, fmt):
        return struct.unpack('<' + fmt, self.take(struct.calcsize('<' + fmt)))

    def i32(self):
        return self.unpack('i')[0]

    def string(self):
        n = self.i32()
        if not n or abs(n) > 65536:
            raise FormatError(f'invalid name length {n}')
        raw = self.take(n if n > 0 else -2*n)
        term = b'\0' if n > 0 else b'\0\0'
        if not raw.endswith(term):
            raise FormatError('name lacks terminator')
        try:
            return raw[:-len(term)].decode('latin-1' if n > 0 else 'utf-16le')
        except UnicodeDecodeError as e:
            raise FormatError(str(e)) from e

def signed16(value):
    value &= 65535
    return value - 65536 if value & 32768 else value

def inspect(data):
    r = Reader(data)
    magic, version, flags = r.unpack('III')
    if magic != 0x9e2a83c1:
        raise FormatError('not an Unreal package')
    if version not in (151, 0x10097):
        raise FormatError(f'unsupported version {version & 65535}/{version >> 16}; expected 151/0 or 151/1')
    nc, no, ec, eo, ic, io = r.unpack('6i')
    guid = r.take(16).hex()
    gc = r.i32()
    if not 0 <= gc <= len(data)//8:
        raise FormatError('invalid generation count')
    generations = [dict(zip(('exports','names'),r.unpack('ii'))) for _ in range(gc)]
    header_end = r.pos
    for count, off, minimum in ((nc,no,9),(ec,eo,22),(ic,io,14)):
        if count < 0 or count > len(data)//minimum or off < 0 or off > len(data):
            raise FormatError('invalid table count/offset')
        if count and (off < header_end or off + count*minimum > len(data)):
            raise FormatError('table outside payload')
    names=[];r.pos=no
    for _ in range(nc):
        names.append({'name':r.string(),'flags':r.unpack('I')[0]})
    name_end=r.pos
    def name(idx):
        if not 0 <= idx < len(names):
            raise FormatError(f'invalid name index {idx}')
        return names[idx]['name']
    def ref(idx):
        if not -ic <= idx <= ec:
            raise FormatError(f'invalid object index {idx}')
        return idx
    imports=[];r.pos=io
    for _ in range(ic):
        cp,cn,outer,on=r.unpack('iihi')
        imports.append({'class_package':name(cp),'class_name':name(cn),'outer':ref(outer),'name':name(on)})
    import_end=r.pos
    exports=[];r.pos=eo
    for _ in range(ec):
        cls,sup,outer,on,fl,size=r.unpack('iihiIi')
        offset=r.i32() if size else 0
        if size < 0 or offset < 0 or offset+size > len(data):
            raise FormatError(f'export payload outside file: {offset}+{size}')
        exports.append({'class':ref(signed16(cls)),'super':ref(signed16(sup)),
                        'outer':ref(outer),'name':name(on),'flags':fl,'size':size,'offset':offset})
    export_end=r.pos
    spans=[(0,header_end,'header')]
    spans += [(a,b,n) for a,b,n,count in [(no,name_end,'names',nc),(io,import_end,'imports',ic),(eo,export_end,'exports',ec)] if count]
    spans.sort()
    for left,right in zip(spans,spans[1:]):
        if left[1] > right[0]:raise FormatError(f'overlapping {left[2]} / {right[2]}')
    for ex in exports:
        if ex['size'] and any(ex['offset'] < end and ex['offset']+ex['size'] > start for start,end,_ in spans):
            raise FormatError('export payload overlaps metadata')
    # Resolve each outer path iteratively; detect corrupt outer cycles without recursion limits.
    objects={**{i+1:v for i,v in enumerate(exports)},**{-(i+1):v for i,v in enumerate(imports)}}
    paths={0:''}
    for idx in objects:
        chain=[];seen=set();cur=idx
        while cur not in paths:
            if cur in seen:raise FormatError('cycle in outer references')
            seen.add(cur);chain.append(cur);cur=objects[cur]['outer']
        for cur in reversed(chain):
            item=objects[cur];parent=paths[item['outer']]
            paths[cur]=(parent+'.' if parent else '')+item['name']
    for idx,item in objects.items():item['object_path']=paths[idx]
    for ex in exports:
        ex['class_path']=paths[ex['class']] or 'Class'
        ex['super_path']=paths[ex['super']] or None
    roots=sorted({v['name'] for v in imports if v['class_name']=='Package' and v['outer']==0})
    return {'version':151,'licensee_version':version >> 16,'flags':flags,'guid':guid,'generations':generations,
            'names':names,'imports':imports,'exports':exports,'package_imports':roots,
            'table_spans':spans,'class_counts':dict(Counter(x['class_path'] for x in exports)),
            'scope':'Metadata only. Object payloads, scripts and native bindings are not decoded.'}
