## Pure Nim i3 bar

import json
import endians
import strutils
import nativesockets
import asyncnet, asyncdispatch
import osproc

const magic = "i3-ipc"

type
  I3* = ref object of RootObj
    sock*: AsyncSocket

  I3MessageType* {.pure.} = enum
    command, get_workspaces, subscribe, get_outputs, get_tree,
    get_marks, get_bar_config, get_version

  PackedMsg {.packed.} = object
    head: array[6, char]
    payload_len: uint32
    msg_type: uint32
    msg: seq[char]

  MsgIntro* = object
    payload_size*: int
    mtype_num*: uint32
    mtype*: I3MessageType

proc close*(i3: I3) =
  i3.sock.close()

proc read_le_uint32(r: string): uint32 =
  littleEndian32(addr(result), unsafeAddr r[0])

proc to_le(i: int): string =
  result = "    "
  littleEndian32(result.cstring, unsafeAddr i)

proc pack*(msg_type: I3MessageType, msg: string): string =
  magic & msg.len.to_le & msg_type.int.to_le & msg

proc send*(i3: I3, msg_type: I3MessageType, msg: string) {.async.} =
  let m = msg_type.pack(msg)
  await i3.sock.send(m)

proc unpack*(r: string): MsgIntro =
  doAssert r[0..5] == magic
  result.payload_size = int read_le_uint32 r[6..9]
  result.mtype_num = read_le_uint32 r[10..13]
  try:
    result.mtype = I3MessageType read_le_uint32 r[10..13]
  except:
    discard

proc receive_msg*(i3: I3, timeout = -1): Future[JsonNode] {.async.} =
  var r: string
  r = await i3.sock.recv(14)
  assert r.len == 14
  let mi = r.unpack
  r = await i3.sock.recv(mi.payload_size)
  doAssert r.len == mi.payload_size
  return parseJson r

proc send_recv*(i3: I3, msg_type: I3MessageType, msg: string): Future[
    JsonNode] {.async.} =
  let m = pack(msg_type, msg)
  await i3.sock.send(m)
  return await i3.receive_msg()


proc get_version*(i3: I3): Future[JsonNode] {.async.} =
  return await i3.send_recv(I3MessageType.get_version, "")


proc getI3SocketPath(): string =
  osproc.execProcess("i3 --get-socketpath").strip()

proc newI3*(): I3 =
  let sock_path = getI3SocketPath()

  let i3 = I3()
  i3.sock = newAsyncSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
  echo("Connecting to: ", sock_path)
  asyncCheck i3.sock.connectUnix(sock_path)
  return i3

when isMainModule:
  let i3 = newI3()

  echo(waitFor i3.get_version)

  i3.close()
