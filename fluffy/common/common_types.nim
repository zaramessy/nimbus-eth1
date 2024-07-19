# Nimbus
# Copyright (c) 2021-2024 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [].}

import results, ssz_serialization, stew/byteutils, eth/rlp, nimcrypto/hash

export hash, ssz_serialization

type
  Bytes2* = ByteVector[2]
  Bytes32* = ByteVector[32]

  ContentId* = UInt256
  ContentKeyByteList* = ByteList[2048] # The encoded content key
  BlockHash* = MDigest[32 * 8] # Bytes32

func `$`*(x: ByteList[2048]): string =
  x.asSeq.to0xHex()

func decodeRlp*(input: openArray[byte], T: type): Result[T, string] =
  try:
    ok(rlp.decode(input, T))
  except RlpError as e:
    err(e.msg)

func decodeSsz*(input: openArray[byte], T: type): Result[T, string] =
  try:
    ok(SSZ.decode(input, T))
  except SerializationError as e:
    err(e.msg)

func decodeSszOrRaise*(input: openArray[byte], T: type): T =
  try:
    SSZ.decode(input, T)
  except SerializationError as e:
    raiseAssert(e.msg)
