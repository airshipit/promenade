{{/*
gzip generates RFC 1952 compliant GZIP streams directly in Helm templates using pure text/template logic.
It is optimized for small text/TAR payloads: fixed Huffman codes (BTYPE=01) with runs of a repeated byte
encoded as matches (distance 1, up to 258 bytes), a block that doesn't get smaller is STORED (BTYPE=00).

Input: string with content or dict with the following fields:
    content:          "string"   # File payload
    compress:         bool       # (default: true) Compress, otherwise only STORED blocks are produced.
    calc_crc32:       bool       # (default: true) Computes IEEE 802.3 CRC32 checksum. Can be disabled for minor performance gain if target decompressor ignores it.

Implementation notes (template function calls are the cost, so there are few of them per byte):
  - the payload is split into bytes once: regexFindAll over its hex representation
  - the DEFLATE stream is produced as a string of '0'/'1' in stream order and packed into bytes with a lookup
  - the CRC32 state is 4 bytes, XOR of 2 bytes is a lookup in a 256x256 table built at render time

Features:
  - Seamless pipeline integration with the 'tar' template helper

Example:

{{- $envAll := . }}
{{- $files := dict
    "README" (dict "content" "Hi everyone!!!\n" "file_mode" 420)
    "README.symlink" (dict "type" "2" "link_path" "README" "file_mode" 511)
    "README.hardlink" (dict "type" "1" "link_path" "README" "file_mode" 420)
    "someverylongdir/cluster_config.yaml" (dict "content" (tuple . "templates/kubeadm/_cluster_config.yaml.tpl" | include "kubeadm.bundle.template") "file_mode" 420)
    "join_config.yaml" (dict "content" (tuple . "templates/kubeadm/_join_config.yaml.tpl" | include "kubeadm.bundle.template") "file_mode" 420)
-}}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "kubeadm.fullname" $envAll }}-aio-config-tgz
type: Opaque
data:
  aio-config.tar.gz: {{ $files | include "tar" | include "gzip" | b64enc | quote }}

*/}}

{{- define "_gzip_print_chars" }}
  {{- $gzipContext := index . 0 -}}
  {{- $byteList := index . 1 -}}
  {{- $bytes := get $gzipContext "bytes" -}}
  {{- range $b := $byteList -}}
    {{- substr ($b | int) (add $b 1 | int) $bytes -}}
  {{- end -}}
{{- end -}}

{{- define "_gzip_print_u16_le" -}}
  {{- $gzipContext := index . 0 -}}
  {{- $v := index . 1 | int -}}
  {{- $b0 := mod $v 256 -}}
  {{- $b1 := div $v 256 | int -}}
  {{- tuple $gzipContext (list $b0 $b1) | include "_gzip_print_chars" -}}
{{- end -}}

{{- define "_gzip_print_u32_le" -}}
  {{- $gzipContext := index . 0 -}}
  {{- $v := index . 1 | int -}}
  {{- $b0 := mod $v 256 -}}
  {{- $v = div $v 256 | int -}}
  {{- $b1 := mod $v 256 -}}
  {{- $v = div $v 256 | int -}}
  {{- $b2 := mod $v 256 -}}
  {{- $b3 := div $v 256 | int -}}
  {{- tuple $gzipContext (list $b0 $b1 $b2 $b3) | include "_gzip_print_chars" -}}
{{- end -}}

{{- define "_gzip_init" -}}
  {{- $gzipContext := . -}}
  {{- $bytes := get $gzipContext "bytes" -}}
  {{- $hexToInt := dict -}}
  {{- $octets := dict -}}
  {{- range $i := until 256 -}}
    {{- $_ := set $hexToInt (printf "%02x" $i) $i -}}
    {{/* the first bit of the stream is the least significant bit of a byte */}}
    {{- $_ := set $octets (printf "%08b" $i | splitList "" | reverse | join "") (substr $i (add1 $i | int) $bytes) -}}
  {{- end -}}
  {{- $_ := set $gzipContext "hexToInt" $hexToInt -}}
  {{- $_ := set $gzipContext "octets" $octets -}}
{{- end -}}

{{- define "_gzip_init_fixed_huffman" -}}
  {{- $gzipContext := . -}}
  {{/* literals by byte (hex): 0..143 are 8 bit codes from 0x30, 144..255 are 9 bit codes from 0x190 */}}
  {{- $lit := dict -}}
  {{- range $i := until 256 -}}
    {{- if le $i 143 -}}
      {{- $_ := set $lit (printf "%02x" $i) (printf "%08b" (add $i 48)) -}}
    {{- else -}}
      {{- $_ := set $lit (printf "%02x" $i) (printf "%09b" (add $i 256)) -}}
    {{- end -}}
  {{- end -}}
  {{/*
    matches by length 3..258: length code (symbols 257..285: 7 bit codes up to 279, 8 bit codes from 280),
    its extra bits (least significant first) and distance code 0 (distance 1, 5 bits)
  */}}
  {{- $bases := list 3 4 5 6 7 8 9 10 11 13 15 17 19 23 27 31 35 43 51 59 67 83 99 115 131 163 195 227 258 -}}
  {{- $extraBits := list 0 0 0 0 0 0 0 0 1 1 1 1 2 2 2 2 3 3 3 3 4 4 4 4 5 5 5 5 0 -}}
  {{/* 284 covers 227..257: 258 has its own symbol */}}
  {{- $counts := list 1 1 1 1 1 1 1 1 2 2 2 2 4 4 4 4 8 8 8 8 16 16 16 16 32 32 32 31 1 -}}
  {{- $match := list "" "" "" -}}
  {{- range $i, $base := $bases -}}
    {{- $sym := add $i 257 -}}
    {{- $code := ternary (printf "%07b" (sub $sym 256)) (printf "%08b" (sub $sym 88)) (lt $sym 280) -}}
    {{- $n := index $extraBits $i -}}
    {{- range $e := until (index $counts $i) -}}
      {{- $extra := "" -}}
      {{- if $n -}}
        {{- $extra = printf "%0*b" $n $e | splitList "" | reverse | join "" -}}
      {{- end -}}
      {{- $match = append $match (print $code $extra "00000") -}}
    {{- end -}}
  {{- end -}}
  {{- $_ := set $gzipContext "litBits" $lit -}}
  {{- $_ := set $gzipContext "matchBits" $match -}}
{{- end -}}

{{/*
def generate_crc32_table():
    table = []
    polynomial = 0xEDB88320

    for i in range(256):
        crc = i
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ polynomial
            else:
                crc >>= 1
        table.append(crc)
    return table

crc_table = generate_crc32_table()

print("    {{- $_ := set $gzipContext \"crcTable\" (list")
for i in range(0, 256, 8):
    row = "      " + " ".join(f"0x{val:08X}" for val in crc_table[i:i+8])
    print(row)
print("    ) -}}")
*/}}
{{- define "_gzip_init_crc_table" -}}
  {{- $gzipContext := . -}}
  {{- if not (hasKey $gzipContext "crcTable") -}}
    {{- $_ := set $gzipContext "crcTable" (list
      0x00000000 0x77073096 0xEE0E612C 0x990951BA 0x076DC419 0x706AF48F 0xE963A535 0x9E6495A3
      0x0EDB8832 0x79DCB8A4 0xE0D5E91E 0x97D2D988 0x09B64C2B 0x7EB17CBD 0xE7B82D07 0x90BF1D91
      0x1DB71064 0x6AB020F2 0xF3B97148 0x84BE41DE 0x1ADAD47D 0x6DDDE4EB 0xF4D4B551 0x83D385C7
      0x136C9856 0x646BA8C0 0xFD62F97A 0x8A65C9EC 0x14015C4F 0x63066CD9 0xFA0F3D63 0x8D080DF5
      0x3B6E20C8 0x4C69105E 0xD56041E4 0xA2677172 0x3C03E4D1 0x4B04D447 0xD20D85FD 0xA50AB56B
      0x35B5A8FA 0x42B2986C 0xDBBBC9D6 0xACBCF940 0x32D86CE3 0x45DF5C75 0xDCD60DCF 0xABD13D59
      0x26D930AC 0x51DE003A 0xC8D75180 0xBFD06116 0x21B4F4B5 0x56B3C423 0xCFBA9599 0xB8BDA50F
      0x2802B89E 0x5F058808 0xC60CD9B2 0xB10BE924 0x2F6F7C87 0x58684C11 0xC1611DAB 0xB6662D3D
      0x76DC4190 0x01DB7106 0x98D220BC 0xEFD5102A 0x71B18589 0x06B6B51F 0x9FBFE4A5 0xE8B8D433
      0x7807C9A2 0x0F00F934 0x9609A88E 0xE10E9818 0x7F6A0DBB 0x086D3D2D 0x91646C97 0xE6635C01
      0x6B6B51F4 0x1C6C6162 0x856530D8 0xF262004E 0x6C0695ED 0x1B01A57B 0x8208F4C1 0xF50FC457
      0x65B0D9C6 0x12B7E950 0x8BBEB8EA 0xFCB9887C 0x62DD1DDF 0x15DA2D49 0x8CD37CF3 0xFBD44C65
      0x4DB26158 0x3AB551CE 0xA3BC0074 0xD4BB30E2 0x4ADFA541 0x3DD895D7 0xA4D1C46D 0xD3D6F4FB
      0x4369E96A 0x346ED9FC 0xAD678846 0xDA60B8D0 0x44042D73 0x33031DE5 0xAA0A4C5F 0xDD0D7CC9
      0x5005713C 0x270241AA 0xBE0B1010 0xC90C2086 0x5768B525 0x206F85B3 0xB966D409 0xCE61E49F
      0x5EDEF90E 0x29D9C998 0xB0D09822 0xC7D7A8B4 0x59B33D17 0x2EB40D81 0xB7BD5C3B 0xC0BA6CAD
      0xEDB88320 0x9ABFB3B6 0x03B6E20C 0x74B1D29A 0xEAD54739 0x9DD277AF 0x04DB2615 0x73DC1683
      0xE3630B12 0x94643B84 0x0D6D6A3E 0x7A6A5AA8 0xE40ECF0B 0x9309FF9D 0x0A00AE27 0x7D079EB1
      0xF00F9344 0x8708A3D2 0x1E01F268 0x6906C2FE 0xF762575D 0x806567CB 0x196C3671 0x6E6B06E7
      0xFED41B76 0x89D32BE0 0x10DA7A5A 0x67DD4ACC 0xF9B9DF6F 0x8EBEEFF9 0x17B7BE43 0x60B08ED5
      0xD6D6A3E8 0xA1D1937E 0x38D8C2C4 0x4FDFF252 0xD1BB67F1 0xA6BC5767 0x3FB506DD 0x48B2364B
      0xD80D2BDA 0xAF0A1B4C 0x36034AF6 0x41047A60 0xDF60EFC3 0xA867DF55 0x316E8EEF 0x4669BE79
      0xCB61B38C 0xBC66831A 0x256FD2A0 0x5268E236 0xCC0C7795 0xBB0B4703 0x220216B9 0x5505262F
      0xC5BA3BBE 0xB2BD0B28 0x2BB45A92 0x5CB36A04 0xC2D7FFA7 0xB5D0CF31 0x2CD99E8B 0x5BDEAE1D
      0x9B64C2B0 0xEC63F226 0x756AA39C 0x026D930A 0x9C0906A9 0xEB0E363F 0x72076785 0x05005713
      0x95BF4A82 0xE2B87A14 0x7BB12BAE 0x0CB61B38 0x92D28E9B 0xE5D5BE0D 0x7CDCEFB7 0x0BDBDF21
      0x86D3D2D4 0xF1D4E242 0x68DDB3F8 0x1FDA836E 0x81BE16CD 0xF6B9265B 0x6FB077E1 0x18B74777
      0x88085AE6 0xFF0F6A70 0x66063BCA 0x11010B5C 0x8F659EFF 0xF862AE69 0x616BFFD3 0x166CCF45
      0xA00AE278 0xD70DD2EE 0x4E048354 0x3903B3C2 0xA7672661 0xD06016F7 0x4969474D 0x3E6E77DB
      0xAED16A4A 0xD9D65ADC 0x40DF0B66 0x37D83BF0 0xA9BCAE53 0xDEBB9EC5 0x47B2CF7F 0x30B5FFE9
      0xBDBDF21C 0xCABAC28A 0x53B39330 0x24B4A3A6 0xBAD03605 0xCDD70693 0x54DE5729 0x23D967BF
      0xB3667A2E 0xC4614AB8 0x5D681B02 0x2A6F2B94 0xB40BBE37 0xC30C8EA1 0x5A05DF1B 0x2D02EF8D
    ) -}}
  {{- end -}}
{{- end -}}

{{- define "_gzip_init_crc" -}}
  {{- $gzipContext := . -}}
  {{- include "_gzip_init_crc_table" $gzipContext -}}
  {{/* xor of 2 bytes as xor[a][b]: the row h + r (h is the highest bit) is the row r with swapped halves of every 2*h chunk */}}
  {{- $xor := list (until 256) -}}
  {{- range $h := list 1 2 4 8 16 32 64 128 -}}
    {{- range $r := until $h -}}
      {{- $src := index $xor $r -}}
      {{- $row := list -}}
      {{- range $c := until (div 128 $h | int) -}}
        {{- $base := mul $c $h 2 -}}
        {{- $row = concat $row (slice $src (add $base $h) (add $base $h $h)) (slice $src $base (add $base $h)) -}}
      {{- end -}}
      {{- $xor = append $xor $row -}}
    {{- end -}}
  {{- end -}}
  {{/* bytes of the table values, least significant first */}}
  {{- $t0 := list -}}
  {{- $t1 := list -}}
  {{- $t2 := list -}}
  {{- $t3 := list -}}
  {{- range $v := get $gzipContext "crcTable" -}}
    {{- $t0 = append $t0 (mod $v 256) -}}
    {{- $t1 = append $t1 (mod (div $v 256) 256) -}}
    {{- $t2 = append $t2 (mod (div $v 65536) 256) -}}
    {{- $t3 = append $t3 (div $v 16777216) -}}
  {{- end -}}
  {{- $_ := set $gzipContext "xor" $xor -}}
  {{- $_ := set $gzipContext "crcBytes" (list $t0 $t1 $t2 $t3) -}}
  {{/* 0xFFFFFFFF */}}
  {{- $_ := set $gzipContext "crc" (list 255 255 255 255) -}}
{{- end -}}

{{/* crc = table[(crc ^ byte) & 0xff] ^ (crc >> 8) with the state as 4 bytes c0 (least significant)..c3 */}}
{{- define "_gzip_update_crc" -}}
  {{- $gzipContext := index . 0 -}}
  {{- $hexes := index . 1 -}}
  {{- $hexToInt := get $gzipContext "hexToInt" -}}
  {{- $xor := get $gzipContext "xor" -}}
  {{- $t := get $gzipContext "crcBytes" -}}
  {{- $t0 := index $t 0 -}}
  {{- $t1 := index $t 1 -}}
  {{- $t2 := index $t 2 -}}
  {{- $t3 := index $t 3 -}}
  {{- $crc := get $gzipContext "crc" -}}
  {{- $c0 := index $crc 0 -}}
  {{- $c1 := index $crc 1 -}}
  {{- $c2 := index $crc 2 -}}
  {{- $c3 := index $crc 3 -}}
  {{- range $h := $hexes -}}
    {{- $i := index $xor $c0 (get $hexToInt $h) -}}
    {{- $c0 = index $xor $c1 (index $t0 $i) -}}
    {{- $c1 = index $xor $c2 (index $t1 $i) -}}
    {{- $c2 = index $xor $c3 (index $t2 $i) -}}
    {{- $c3 = index $t3 $i -}}
  {{- end -}}
  {{- $_ := set $gzipContext "crc" (list $c0 $c1 $c2 $c3) -}}
{{- end -}}

{{/* the bits of a fixed Huffman block body (without the header and the end of block) in stream order */}}
{{- define "_gzip_fixed_huffman_bits" -}}
  {{- $gzipContext := index . 0 -}}
  {{- $hexes := index . 1 -}}
  {{- $lit := get $gzipContext "litBits" -}}
  {{- $match := get $gzipContext "matchBits" -}}
  {{- $prev := "" -}}
  {{- $run := 0 -}}
  {{- range $h := $hexes -}}
    {{- if and (eq $h $prev) (lt $run 259) -}}
      {{- $run = add1 $run -}}
    {{- else -}}
      {{/* a run: the byte as a literal, the rest as a match with distance 1 */}}
      {{- if gt $run 3 -}}
        {{- get $lit $prev -}}{{- index $match (sub $run 1) -}}
      {{- else -}}
        {{- repeat ($run | int) (get $lit $prev) -}}
      {{- end -}}
      {{- $prev = $h -}}
      {{- $run = 1 -}}
    {{- end -}}
  {{- end -}}
  {{- if gt $run 3 -}}
    {{- get $lit $prev -}}{{- index $match (sub $run 1) -}}
  {{- else -}}
    {{- repeat ($run | int) (get $lit $prev) -}}
  {{- end -}}
{{- end -}}

{{- define "gzip" -}}
  {{- $content := . -}}
  {{- $compress := true -}}
  {{- $calcCrc32 := true -}}{{/* even though it's mandatory in RFC 1952, many decompressors don't check crc, so it will be zero if this flag is false */}}
  {{- if kindIs "map" . -}}
    {{- $content = get . "content" -}}
    {{- $compress = hasKey . "compress" | ternary (get . "compress") true -}}
    {{- $calcCrc32 = hasKey . "calc_crc32" | ternary (get . "calc_crc32") true -}}
  {{- end -}}
  {{- $size := len $content -}}

  {{/*
      here is how to generate this string:
      import base64
      raw_bytes = bytes(range(256))
      b64_str = base64.b64encode(raw_bytes).decode('ascii')
      print(b64_str)
  */}}
  {{- $gzipContext := dict "bytes" ("AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+/w==" | b64dec) -}}
  {{- include "_gzip_init" $gzipContext -}}
  {{- if $compress -}}
    {{- include "_gzip_init_fixed_huffman" $gzipContext -}}
  {{- end -}}
  {{- if $calcCrc32 -}}
    {{- include "_gzip_init_crc" $gzipContext -}}
  {{- end -}}
  {{- $octets := get $gzipContext "octets" -}}

  {{/* header */}}
  {{- tuple $gzipContext (list 31 139 8 0 0 0 0 0 0 3) | include "_gzip_print_chars" -}}

  {{/* blocks, at least one (the final one) */}}
  {{- $maxBlockSize := 65535 -}}
  {{- $blocks := div (add $size $maxBlockSize -1) $maxBlockSize | max 1 | int -}}
  {{/* the bits that don't fill a byte yet: the blocks follow each other without alignment */}}
  {{- $pending := "" -}}
  {{- range $i := until $blocks -}}
    {{- $offset := mul $i $maxBlockSize | int -}}
    {{- $blockSize := min $maxBlockSize (sub $size $offset) | int -}}
    {{- $bfinal := ternary "1" "0" (eq (add1 $i | int) $blocks) -}}
    {{- $payload := substr $offset (add $offset $blockSize | int) $content -}}
    {{- $hexes := regexFindAll "[0-9a-f]{2}" (printf "%x" $payload) -1 -}}
    {{- if $calcCrc32 -}}
      {{- include "_gzip_update_crc" (list $gzipContext $hexes) -}}
    {{- end -}}

    {{- $bits := "" -}}
    {{- if $compress -}}
      {{/* BFINAL, BTYPE=01 (least significant bit first), the body, the end of block (7 zero bits) */}}
      {{- $bits = print $pending $bfinal "10" (include "_gzip_fixed_huffman_bits" (list $gzipContext $hexes)) "0000000" -}}
      {{/* STORED is smaller: header, up to 7 bits of padding, LEN, NLEN, payload */}}
      {{- if ge (len $bits) (add (len $pending) 3 7 32 (mul $blockSize 8)) -}}
        {{- $bits = "" -}}
      {{- end -}}
    {{- end -}}

    {{- if $bits -}}
      {{- range $o := regexFindAll "[01]{8}" $bits -1 -}}
        {{- get $octets $o -}}
      {{- end -}}
      {{- $pending = substr (mul (div (len $bits) 8) 8 | int) (len $bits) $bits -}}
    {{- else -}}
      {{/* BFINAL, BTYPE=00, padding to a byte, LEN, NLEN, payload */}}
      {{- $bits = print $pending $bfinal "00" -}}
      {{- $bits = print $bits (repeat (mod (sub 8 (mod (len $bits) 8)) 8 | int) "0") -}}
      {{- range $o := regexFindAll "[01]{8}" $bits -1 -}}
        {{- get $octets $o -}}
      {{- end -}}
      {{- tuple $gzipContext $blockSize | include "_gzip_print_u16_le" -}}
      {{- tuple $gzipContext (sub 65535 $blockSize) | include "_gzip_print_u16_le" -}}
      {{- $payload -}}
      {{- $pending = "" -}}
    {{- end -}}
  {{- end -}}
  {{- if $pending -}}
    {{- get $octets (print $pending (repeat (sub 8 (len $pending) | int) "0")) -}}
  {{- end -}}

  {{/* trailer: CRC32 (the state ^ 0xFFFFFFFF) + ISIZE */}}
  {{- if $calcCrc32 -}}
    {{- $crc := get $gzipContext "crc" -}}
    {{- tuple $gzipContext (list (sub 255 (index $crc 0)) (sub 255 (index $crc 1)) (sub 255 (index $crc 2)) (sub 255 (index $crc 3))) | include "_gzip_print_chars" -}}
  {{- else -}}
    {{- tuple $gzipContext (list 0 0 0 0) | include "_gzip_print_chars" -}}
  {{- end -}}
  {{- tuple $gzipContext (mod $size 4294967296) | include "_gzip_print_u32_le" -}}
{{- end -}}
