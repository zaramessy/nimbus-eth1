import
  macro_assembler, unittest2, macros,
  stew/byteutils, eth/common, stew/ranges

proc opCustomMain*() =
  suite "Custom Opcodes Test":
    setup:
      let (blockNumber, chainDB) = initDatabase()

    assembler: # CALLDATASIZE OP
      title: "CALLDATASIZE_1"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code:
        CallDataSize
      stack: "0x0000000000000000000000000000000000000000000000000000000000000040"

    assembler: # CALLDATALOAD OP
      title: "CALLDATALOAD_1"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code:
        Push1 "0x00"
        CallDataLoad
      stack: "0x00000000000000000000000000000000000000000000000000000000000000A1"

    assembler: # CALLDATALOAD OP
      title: "CALLDATALOAD_2"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code:
        Push1 "0x02"
        CallDataLoad
      stack: "0x0000000000000000000000000000000000000000000000000000000000A10000"

    assembler: # CALLDATALOAD OP
      title: "CALLDATALOAD_3"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code:
        Push1 "0x20"
        CallDataLoad
      stack: "0x00000000000000000000000000000000000000000000000000000000000000B1"

    assembler: # CALLDATALOAD OP
      title: "CALLDATALOAD_4"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code:
        Push1 "0x23"
        CallDataLoad
      stack: "0x00000000000000000000000000000000000000000000000000000000B1000000"

    assembler: # CALLDATALOAD OP
      title: "CALLDATALOAD_5"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code:
        Push1 "0x3F"
        CallDataLoad
      stack: "0xB100000000000000000000000000000000000000000000000000000000000000"

    assembler: # CALLDATALOAD OP mal
      title: "CALLDATALOAD_6"
      code:
        CallDataLoad
      success: false

    assembler: # CALLDATALOAD OP
      title: "CALLDATALOAD_7"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code:
        Push1 "0x40"
        CallDataLoad
      stack: "0x00"

    assembler: # CALLDATACOPY OP
      title: "CALLDATACOPY_1"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code:
        Push1 "0x20"
        Push1 "0x00"
        Push1 "0x00"
        CallDataCopy
      memory: "0x00000000000000000000000000000000000000000000000000000000000000A1"

    assembler: # CALLDATACOPY OP
      title: "CALLDATACOPY_2"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code:
        Push1 "0x40"
        Push1 "0x00"
        Push1 "0x00"
        CallDataCopy
      memory:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"

    assembler: # CALLDATACOPY OP
      title: "CALLDATACOPY_3"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code:
        Push1 "0x40"
        Push1 "0x04"
        Push1 "0x00"
        CallDataCopy
      memory:
        "0x000000000000000000000000000000000000000000000000000000A100000000"
        "0x000000000000000000000000000000000000000000000000000000B100000000"

    assembler: # CALLDATACOPY OP
      title: "CALLDATACOPY_4"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code:
        Push1 "0x40"
        Push1 "0x00"
        Push1 "0x04"
        CallDataCopy
      memory:
        "0x0000000000000000000000000000000000000000000000000000000000000000"
        "0x000000A100000000000000000000000000000000000000000000000000000000"
        "0x000000B100000000000000000000000000000000000000000000000000000000"

    assembler: # CALLDATACOPY OP
      title: "CALLDATACOPY_5"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code:
        Push1 "0x40"
        Push1 "0x00"
        Push1 "0x04"
        CallDataCopy
      memory:
        "0x0000000000000000000000000000000000000000000000000000000000000000"
        "0x000000A100000000000000000000000000000000000000000000000000000000"
        "0x000000B100000000000000000000000000000000000000000000000000000000"

    assembler: # CALLDATACOPY OP mal
      title: "CALLDATACOPY_6"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code:
        Push1 "0x40"
        Push1 "0x00"
        CallDataCopy
      success: false
      stack:
        "0x40"
        "0x00"

    assembler: # CALLDATACOPY OP mal
      title: "CALLDATACOPY_7"
      data:
        "0x00000000000000000000000000000000000000000000000000000000000000A1"
        "0x00000000000000000000000000000000000000000000000000000000000000B1"
      code: "0x6020600073CC0929EB16730E7C14FEFC63006AC2D794C5795637"
      success: false

    assembler: # ADDRESS OP
      title: "ADDRESS_1"
      code:
        Address
      stack: "0x000000000000000000000000c669eaad75042be84daaf9b461b0e868b9ac1871"

    assembler: # BALANCE OP
      title: "BALANCE_1"
      code:
        Address
        Balance
      stack: "0x000000000000000000000000000000000000000000000000cff56a1b273a8000"

    assembler: # ORIGIN OP
      title: "ORIGIN_1"
      code:
        Origin
      stack: "0x000000000000000000000000fbe0afcd7658ba86be41922059dd879c192d4c73"

    assembler: # CALLER OP
      title: "CALLER_1"
      code:
        Caller
      stack: "0x000000000000000000000000fbe0afcd7658ba86be41922059dd879c192d4c73"

    assembler: # CALLVALUE OP
      title: "CALLVALUE_1"
      code:
        CallValue
      stack: "0xcff56a1b273a8000"

    assembler: # SHA3 OP
      title: "SHA3_1"
      code:
        Push1 "0x01"
        Push1 "0x00"
        Mstore8
        Push1 "0x01"
        Push1 "0x00"
        Sha3
      stack: "0x5FE7F977E71DBA2EA1A68E21057BEEBB9BE2AC30C6410AA38D4F3FBE41DCFFD2"
      memory: "0x0100000000000000000000000000000000000000000000000000000000000000"

    assembler: # SHA3 OP
      title: "SHA3_2"
      code:
        Push2 "0x0201"
        Push1 "0x00"
        Mstore
        Push1 "0x02"
        Push1 "0x1E"
        Sha3
      stack: "0x114A3FE82A0219FCC31ABD15617966A125F12B0FD3409105FC83B487A9D82DE4"
      memory: "0x0000000000000000000000000000000000000000000000000000000000000201"

    assembler: # SHA3 OP mal
      title: "SHA3_3"
      code:
        Push2 "0x0201"
        Push1 "0x00"
        Mstore
        Push1 "0x02"
        Sha3
      success: false
      stack: "0x02"
      memory: "0x0000000000000000000000000000000000000000000000000000000000000201"

    assembler: # BLOCKHASH OP
      title: "BLOCKHASH_1"
      code:
        Push2 "0xb864" # 47204, parent header number
        Blockhash
      stack: "0xa85842a20755232169db76c5bd4ad4672c1551fca4b07d0bd139cd0e6fef684d"

    # current block coinbase/miner
    assembler: # COINBASE OP
      title: "COINBASE_1"
      code:
        Coinbase
      stack: "0x000000000000000000000000bb7b8287f3f0a933474a79eae42cbca977791171"

    # current block timestamp
    assembler: # TIMESTAMP OP
      title: "TIMESTAMP_1"
      code:
        TimeStamp
      stack: "0x0000000000000000000000000000000000000000000000000000000055c46bba"

    # current block number
    assembler: # NUMBER OP
      title: "NUMBER_1"
      code:
        Number
      stack: "0x000000000000000000000000000000000000000000000000000000000000b865"

    # current difficulty
    assembler: # DIFFICULTY OP
      title: "DIFFICULTY_1"
      code:
        Difficulty
      stack: "0x000000000000000000000000000000000000000000000000000001547c73822d"

    # ??
    assembler: # GASPRICE OP
      title: "GASPRICE_1"
      code:
        GasPrice
      stack: "0x000000000000000000000000000000000000000000000000000000746a528800"

    # ??
    assembler: # GAS OP
      title: "GAS_1"
      code:
        Gas
      stack: "0x000000000000000000000000000000000000000000000000000000001dcd64fe"

    # ??
    assembler: # GASLIMIT OP
      title: "GASLIMIT_1"
      code:
        GasLimit
      stack: "0x000000000000000000000000000000000000000000000000000000000000a298"

    assembler: # INVALID OP
      title: "INVALID_1"
      code: "0x60012F6002"
      stack: "0x0000000000000000000000000000000000000000000000000000000000000001"
      success: false
