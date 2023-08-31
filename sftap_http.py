#!/usr/bin/env python
# -*- coding:utf-8 -*-

import socket
import json
import sys, traceback
import base64
import datetime
from binascii import b2a_qp
import pathlib

class http_parser:
    def __init__(self, is_client = True, is_body = True):
        self.__METHOD  = 0
        self.__RESP    = 1
        self.__HEADER  = 2
        self.__BODY    = 3
        self.__TRAILER = 4
        self.__CHUNK_LEN  = 5
        self.__CHUNK_BODY = 6
        self.__CHUNK_END  = 7

        self._is_client = is_client

        if is_client:
            self._state = self.__METHOD
        else:
            self._state = self.__RESP

        self._data  = []
        self.result = []

        self._ip       = ''
        self._port     = ''
        self._method   = {}
        self._response = {}
        self._body     = b''
        self._header   = {}
        self._trailer  = {}
        self._length   = 0
        self._remain   = 0
        self._is_body  = is_body
        self._time     = 0.0

        self.__is_error = False

    def get_addr(self):
        return {'ip': self._ip, 'port': self._port}

    def set_addr_peer(self, header):
        if self._ip == '':
            if header['from'] == '1':
                self._ip   = header['ip2']
                self._port = int(header['port2'])
            elif header['from'] == '2':
                self._ip   = header['ip1']
                self._port = int(header['port1'])

    def in_data(self, data, header):
        if self.__is_error:
            return

        if self._ip == '' or self._port == '':
            if header['from'] == '1':
                self._ip   = header['ip1']
                self._port = int(header['port1'])
            elif header['from'] == '2':
                self._ip   = header['ip2']
                self._port = int(header['port2'])

        self._data.append(data)

        try:
            self._parse(header)
        except Exception:
            self.__is_error = True

            print('parse error:', file=sys.stderr)

            exc_type, exc_value, exc_traceback = sys.exc_info()
            print("*** extract_tb:", file=sys.stderr)
            print(repr(traceback.extract_tb(exc_traceback)), file=sys.stderr)
            print("*** format_tb:", file=sys.stderr)
            print(repr(traceback.format_tb(exc_traceback)), file=sys.stderr)
            print("*** tb_lineno:", exc_traceback.tb_lineno, file=sys.stderr)

    def destroy(self):
        if self._is_client:
            if self._method:
                self._push_data()
        else:
            if self._response:
                self._push_data()

    def _push_data(self):
        result = {}

        if self._is_client:
            result['method'] = self._method
        else:
            result['response'] = self._response

        if any(self._header):
            result['header']  = self._header

        if any(self._trailer):
            result['trailer'] = self._trailer

        if self._is_body:
            result['body'] = base64.b64encode(self._body).decode('utf-8')

        result['ip']   = self._ip
        result['port'] = self._port
        result['time'] = self._time

        self.result.append(result)

        self._method   = {}
        self._response = {}
        self._body     = b''
        self._header   = {}
        self._trailer  = {}
        self._length   = 0
        self._remain   = 0

    def _parse(self, header):
        while True:
            if self._state == self.__METHOD:
                if not self._parse_method():
                    break
                self._time = float(header['time'])
            elif self._state == self.__RESP:
                if not self._parse_response():
                    break
                self._time = float(header['time'])
            elif self._state == self.__HEADER:
                if not self._parse_header():
                    break
            elif self._state == self.__BODY:
                self._skip_body()
                if self._remain != 0:
                    break
            elif self._state == self.__CHUNK_LEN:
                if not self._parse_chunk_len():
                    break
            elif self._state == self.__CHUNK_BODY:
                self._skip_body()
                if self._remain != 0:
                    break
                self._state = self.__CHUNK_LEN
            elif self._state == self.__CHUNK_END:
                self._skip_body()
                if self._remain != 0:
                    break

                self._state = self.__TRAILER
            else:
                break

    def _parse_chunk_len(self):
        (result, line) = self._read_line()

        if result:
            self._remain = int(line.split(b';')[0], 16) + 2
            self._state = self.__CHUNK_BODY

            if self._remain == 2:
                self._state = self.__CHUNK_END
            return True
        else:
            return False

    def _parse_trailer(self):
        (result, line) = self._read_line()

        if result:
            if len(line) == 0:
                if self._is_client:
                    self._state = self.__METHOD
                else:
                    self._state = self.__RESP
            else:
                sp = line.split(b': ')

                val = b2a_qp((b': '.join(sp[1:]))).decode('utf-8')
                val = val.strip()

                self._trailer[b2a_qp(sp[0]).decode('utf-8')] = val
            return True
        else:
            return False

    def _parse_method(self):
        (result, line) = self._read_line()

        if result:
            sp = line.split(b' ')

            self._method['method'] = b2a_qp(sp[0]).decode('utf-8')
            self._method['uri']    = b2a_qp(sp[1]).decode('utf-8')
            self._method['ver']    = b2a_qp(sp[2]).decode('utf-8')

            self._state = self.__HEADER
            return True
        else:
            return False

    def _parse_response(self):
        (result, line) = self._read_line()

        if result:
            sp = line.split(b' ')

            self._response['ver']  = b2a_qp(sp[0]).decode('utf-8')
            self._response['code'] = b2a_qp(sp[1]).decode('utf-8')
            self._response['msg']  = b2a_qp((b' '.join(sp[2:]))).decode('utf-8')

            self._state = self.__HEADER
            return True
        else:
            return False

    def _parse_header(self):
        (result, line) = self._read_line()

        if result:
            if line == b'':
                if 'content-length' in self._header:
                    self._remain = int(self._header['content-length'])

                    if self._remain > 0:
                        self._state = self.__BODY
                    elif ('transfer-encoding' in self._header and
                          self._header['transfer-encoding'].lower() == 'chunked'):
                        self._state = self.__CHUNK_LEN
                    elif self._is_client:
                        self._push_data()
                        self._state = self.__METHOD
                    else:
                        self._push_data()
                        self._state = self.__RESP
                elif ('transfer-encoding' in self._header and
                      self._header['transfer-encoding'].lower() == 'chunked'):

                    self._state = self.__CHUNK_LEN
                elif self._is_client:
                    if self._method['ver'] == 'HTTP/1.0':
                        self._remain = -1
                        self._state = self.__BODY
                    else:
                        self._push_data()
                        self._state = self.__METHOD
                else:
                    if self._response['ver'] == 'HTTP/1.0':
                        self._remain = -1
                        self._state = self.__BODY
                    else:
                        self._push_data()
                        self._state = self.__RESP
            else:
                sp = line.split(b': ')

                val = b2a_qp((b': '.join(sp[1:]))).decode('utf-8')
                val = val.strip()

                self._header[b2a_qp(sp[0]).decode('utf-8').lower()] = val

            return True
        else:
            return False

    def _skip_body(self):
        while len(self._data) > 0:
            num = sum([len(x) for x in self._data[0]])
            if self._remain == -1:
                # if content-length or chunked is not exsisting in HTTP header, just read body
                data = self._data.pop(0)
                if self._is_body:
                    self._body += data[0]
            elif num <= self._remain:
                # self._data is buffer for body
                # if the length of data in buffer is less than the length of
                # body, consume only a line and wait next data
                data = self._data.pop(0) # must be stored
                self._remain -= num

                if self._state != self.__CHUNK_END and self._is_body:
                    self._body += data[0]

                if self._remain == 0:
                    if self._state == self.__BODY:
                        if self._is_client:
                            self._push_data()
                            self._state = self.__METHOD
                        else:
                            self._push_data()
                            self._state = self.__RESP
                    elif self._state == self.__CHUNK_BODY and self._is_body: # chunked
                        self._body = self._body[:-2] # remove \r\n
            else:
                # self._data is buffer for body
                # if the length of data in buffer is greater than the length of
                # body, consume until buffer is full.
                while True:
                    num = len(self._data[0][0])
                    if num <= self._remain:
                        data = self._data[0].pop(0)
                        self._remain -= num

                        if self._state != self.__CHUNK_END and self._is_body:
                            self._body += data[0]
                    else:
                        if self._state != self.__CHUNK_END and self._is_body:
                            self._body += self._data[0][0][:self._remain]

                        self._data[0][0] = self._data[0][0][self._remain:]
                        self._remain = 0

                    if self._remain == 0:
                        if self._state == self.__BODY:
                            if self._is_client:
                                self._push_data()
                                self._state = self.__METHOD
                            else:
                                self._push_data()
                                self._state = self.__RESP
                        elif self._state == self.__CHUNK_BODY and self._is_body: # chunked
                            self._body = self._body[:-2] # remove \r\n

                        return

    def _read_line(self):
        line = b''
        for i, v in enumerate(self._data):
            for j, buf in enumerate(v):
                idx = buf.find(b'\n')
                if idx >= 0:
                    line += buf[:idx].rstrip()

                    self._data[i] = v[j:]

                    suffix = buf[idx + 1:]

                    if len(suffix) > 0:
                        self._data[i][0] = suffix
                    else:
                        self._data[i].pop(0)

                    if len(self._data[i]) > 0:
                        self._data = self._data[i:]
                    else:
                        self._data = self._data[i + 1:]

                    return (True, line)
                else:
                    line += buf

        return (False, None)

class sftap_http:
    def __init__(self, uxpath, is_body):
        self._content = []
        self._conn = None
        self._f = None
        p_file = pathlib.Path(uxpath)
        if p_file.is_socket():
            self._conn = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self._conn.connect(uxpath)

            print('connected to', uxpath, file=sys.stderr)
        elif p_file.is_file():
            self._f = open(uxpath, "rb")
            print('open', uxpath, file=sys.stderr)
        else:
            print('can not open', uxpath, "\nDie", file=sys.stderr)
            exit()
            
        self._header = {}

        self.__HEADER = 0
        self.__DATA   = 1
        self._state   = self.__HEADER
        self._is_body = is_body

        self._http = {}

    def run(self):
        while True:
            if self._conn != None:
                buf = b'' + self._conn.recv(65536)
            else:
                buf = b'' + self._f.readline()
                
            if len(buf) == 0:
                print('remote socket was closed', file=sys.stderr)
                return

            self._content.append(buf)
            self._parse()

    def _parse(self):
        while True:
            if self._state == self.__HEADER:
                (result, line) = self._read_line()
                if result == False:
                    break

                self._header = self._parse_header(line)

                if self._header['event'] == 'DATA':
                    self._state = self.__DATA
                elif self._header['event'] == 'CREATED':
                    sid = self._get_id()
                    self._http[sid] = (http_parser(is_client = True,
                                                   is_body = self._is_body),
                                       http_parser(is_client = False,
                                                   is_body = self._is_body))
                elif self._header['event'] == 'DESTROYED':
                    try:
                        sid = self._get_id()
                        c = self._http[sid][0]
                        s = self._http[sid][1]
                        vlan = sid[5]
                        netid = sid[6]

                        c.destroy()
                        s.destroy()

                        while len(c.result) > 0 or len(s.result) > 0:
                            if len(c.result) > 0 and len(s.result):
                                rc = c.result.pop(0)
                                rs = s.result.pop(0)
                                print(json.dumps({'netid': netid, 'vlan': vlan, 'client': rc, 'server': rs},
                                                 separators=(',', ':'),
                                                 ensure_ascii = False))
                            elif len(c.result) > 0:
                                rc = c.result.pop(0)
                                if rc['method'] != {}:
                                    print(json.dumps({'netid': netid, 'vlan': vlan, 'client': rc, 'server': s.get_addr()},
                                                    separators=(',', ':'),
                                                    ensure_ascii = False))
                            elif len(s.result) > 0:
                                rs = s.result.pop(0)
                                if rs['response'] != {}:
                                    print(json.dumps({'netid': netid, 'vlan': vlan, 'server': rs, 'client': c.get_addr()},
                                                    separators=(',', ':'),
                                                    ensure_ascii = False))

                        if self._header['reason'] != 'NORMAL':
                            print(json.dumps({'netid': netid, 'vlan': vlan, 'server': s.get_addr(), 'client': c.get_addr(),
                                              'error': self._header['reason']},
                                             separators=(',', ':'),
                                             ensure_ascii = False))
                        del self._http[sid]
                    except KeyError:
                        pass
            elif self._state == self.__DATA:
                num = int(self._header['len'])

                (result, buf) = self._read_bytes(num)
                if result == False:
                    break

                sid = self._get_id()
                vlan = sid[5]
                netid = sid[6]

                if sid in self._http:
                    if self._header['match'] == 'up':
                        self._http[sid][0].in_data(buf, self._header)
                        self._http[sid][1].set_addr_peer(self._header)
                    elif self._header['match'] == 'down':
                        self._http[sid][1].in_data(buf, self._header)
                        self._http[sid][0].set_addr_peer(self._header)

                    while True:
                        if (len(self._http[sid][0].result) > 0 and
                            len(self._http[sid][1].result) > 0):
                            c = self._http[sid][0].result.pop(0)
                            s = self._http[sid][1].result.pop(0)
                            print(json.dumps({'netid': netid, 'vlan': vlan, 'client': c, 'server': s},
                                             separators=(',', ':'),
                                             ensure_ascii = False))
                        else:
                            break
                else:
                    pass

                self._state = self.__HEADER
            else:
                print("ERROR: unkown state", file=sys.stderr)
                exit(1)

            sys.stdout.flush()

    def _read_line(self):
        line = b''
        for i, buf in enumerate(self._content):
            idx = buf.find(b'\n')
            if idx >= 0:
                line += buf[:idx]

                self._content = self._content[i:]

                suffix = buf[idx + 1:]

                if len(suffix) > 0:
                    self._content[0] = suffix
                else:
                    self._content.pop(0)

                return (True, line)
            else:
                line += buf

        return (False, b'')

    def _read_bytes(self, num):
        n = 0
        for buf in self._content:
            n += len(buf)

        if n < num:
            return (False, None)

        data = []
        while True:
            buf = self._content.pop(0)
            if len(buf) <= num:
                data.append(buf)
                num -= len(buf)
            else:
                d = buf[:num]
                data.append(d)
                self._content.insert(0, buf[num:])
                num -= len(d)

            if num == 0:
                return (True, data)

        return (False, None)

    def _parse_header(self, line):
        d = {}
        for x in line.split(b','):
            m = x.split(b'=')
            d[m[0].decode('utf-8')] = m[1].decode('utf-8')

        return d

    def _get_id(self):
        vlan = -1
#        if 'vlan' in self._header:
#            vlan = self._header['vlan']

        netid = -1
        if 'netid' in self._header:
            netid = self._header['netid']

        return (self._header['ip1'],
                self._header['ip2'],
                self._header['port1'],
                self._header['port2'],
                self._header['hop'],
                vlan, netid)

def main():
    uxpath = '/tmp/sf-tap/tcp/http'

    if len(sys.argv) > 1:
        uxpath = sys.argv[1]

    is_body = True
    if len(sys.argv) > 2 and sys.argv[2] == 'nobody':
        is_body = False

    parser = sftap_http(uxpath, is_body)
    parser.run()

if __name__ == '__main__':
    main()
