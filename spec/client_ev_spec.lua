package.path = package.path..'../src'

local client = require'websocket.client'
local ev = require'ev'
local frame = require'websocket.frame'
local port = os.getenv('LUAWS_WSTEST_PORT') or 8081
local req_ws = ' (requires external websocket server @port '..port..')'
local url = 'ws://localhost:'..port

setloop('ev')

describe(
  'The client (ev) module',
  function()
    local wsc
    it(
      'exposes the correct interface',
      function()
        assert.is_table(client)
        assert.is_function(client.ev)
      end)
    
    it(
      'can be constructed',
      function()
        wsc = client.ev()
      end)
    
    it(
      'can connect and calls on_open'..req_ws,
      async,
      function(done)
        wsc:on_open(guard(function(ws)
              assert.is_equal(ws,wsc)
              done()
          end))
        wsc:connect(url,'echo-protocol')
      end)
    
    it(
      'calls on_error if already connected'..req_ws,
      async,
      function(done)
        wsc:on_error(guard(function(ws,err)
              assert.is_equal(ws,wsc)
              assert.is_equal(err,'wrong state')
              ws:on_error()
              ws:on_close(done)
              ws:close()
          end))
        wsc:connect(url,'echo-protocol')
      end)
    
    it(
      'calls on_error on bad protocol'..req_ws,
      async,
      function(done)
        wsc:on_error(guard(function(ws,err)
              assert.is_equal(ws,wsc)
              assert.is_equal(err,'bad protocol')
              ws:on_error()
              done()
          end))
        wsc:connect('ws2://localhost:'..port,'echo-protocol')
      end)
    
    it(
      'can parse HTTP request header byte per byte',
      async,
      function(done)
        local resp = {
          'HTTP/1.1 101 Switching Protocols',
          'Upgrade: websocket',
          'Connection: Upgrade',
          'Sec-Websocket-Accept: e2123as3',
          'Sec-Websocket-Protocol: chat',
          '\r\n'
        }
        resp = table.concat(resp,'\r\n')
        assert.is_equal(resp:sub(#resp-3),'\r\n\r\n')
        local socket = require'socket'
        local http_serv = socket.bind('*',port + 20)
        local http_con
        wsc:on_error(guard(function(ws,err)
              assert.is_equal(err,'accept failed')
              ws:close()
              http_serv:close()
              http_con:close()
              done()
          end))
        wsc:on_open(guard(function()
              assert.is_nil('should never happen')
          end))
        wsc:connect('ws://localhost:'..(port+20),'chat')
        http_con = http_serv:accept()
        local i = 1
        ev.Timer.new(function(loop,timer)
            if i <= #resp then
              local byte = resp:sub(i,i)
              http_con:send(byte)
              i = i + 1
            else
              timer:stop(loop)
            end
          end,0.0001,0.0001):start(ev.Loop.default)
      end)
    
    it(
      'properly calls on_error if socket error on handshake occurs',
      async,
      function(done)
        local resp = {
          'HTTP/1.1 101 Switching Protocols',
          'Upgrade: websocket',
          'Connection: Upgrade',
        }
        resp = table.concat(resp,'\r\n')
        local socket = require'socket'
        local http_serv = socket.bind('*',port + 20)
        local http_con
        wsc:on_error(guard(function(ws,err)
              assert.is_equal(err,'accept failed')
              ws:on_close(done)
              ws:close()
              http_serv:close()
              http_con:close()
          end))
        wsc:on_open(guard(function()
              assert.is_nil('should never happen')
          end))
        wsc:connect('ws://localhost:'..(port+20),'chat')
        http_con = http_serv:accept()
        local i = 1
        ev.Timer.new(function(loop,timer)
            if i <= #resp then
              local byte = resp:sub(i,i)
              http_con:send(byte)
              i = i + 1
            else
              timer:stop(loop)
              http_con:close()
            end
          end,0.0001,0.0001):start(ev.Loop.default)
      end)
    
    it(
      'can open and close immediatly (in CLOSING state)'..req_ws,
      async,
      function(done)
        wsc:connect(url,'echo-protocol')
        wsc:on_error(function(_,err)
            assert.is_nil(err or 'should never happen')
          end)
        wsc:on_close(function(_,was_clean,code)
            assert.is_false(was_clean)
            assert.is_equal(code,1006)
            done()
          end)
        wsc:close()
      end)
    
    
    it(
      'can send and receive data'..req_ws,
      async,
      function(done)
        assert.is_function(wsc.send)
        wsc:on_message(
          guard(
            function(ws,message,opcode)
              assert.is_equal(ws,wsc)
              assert.is_same(message,'Hello again')
              assert.is_same(opcode,frame.TEXT)
              done()
          end))
        wsc:on_open(function()
            wsc:send('Hello again')
          end)
        wsc:connect(url,'echo-protocol')
      end)
    
    local random_text = function(len)
      local chars = {}
      for i=1,len do
        chars[i] = string.char(math.random(33,126))
      end
      return table.concat(chars)
    end
    
    it(
      'can send and receive data 127 byte messages'..req_ws,
      async,
      function(done)
        local msg = random_text(127)
        wsc:on_message(
          guard(
            function(ws,message,opcode)
              assert.is_same(#msg,#message)
              assert.is_same(msg,message)
              assert.is_same(opcode,frame.TEXT)
              done()
          end))
        wsc:send(msg)
      end)
    
    it(
      'can send and receive data 0xffff-1 byte messages'..req_ws,
      async,
      function(done)
        local msg = random_text(0xffff-1)
        wsc:on_message(
          guard(
            function(ws,message,opcode)
              assert.is_same(#msg,#message)
              assert.is_same(msg,message)
              assert.is_same(opcode,frame.TEXT)
              done()
          end))
        wsc:send(msg)
      end)
    
    it(
      'can send and receive data 0xffff+1 byte messages'..req_ws,
      async,
      function(done)
        local msg = random_text(0xffff+1)
        wsc:on_message(
          guard(
            function(ws,message,opcode)
              assert.is_same(#msg,#message)
              assert.is_same(msg,message)
              assert.is_same(opcode,frame.TEXT)
              done()
          end))
        wsc:send(msg)
      end)
    
    it(
      'closes nicely'..req_ws,
      async,
      function(done)
        wsc:on_close(guard(function(_,was_clean,code,reason)
              assert.is_true(was_clean)
              assert.is_true(code >= 1000)
              assert.is_string(reason)
              done()
          end))
        wsc:close()
      end)
  end)
