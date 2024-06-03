# nimbus-eth1
# Copyright (c) 2024 Status Research & Development GmbH
# Licensed under either of
#  * Apache License, version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
#    http://www.apache.org/licenses/LICENSE-2.0)
#  * MIT license ([LICENSE-MIT](LICENSE-MIT) or
#    http://opensource.org/licenses/MIT)
# at your option. This file may not be copied, modified, or distributed
# except according to those terms.

## Stackable API for `Aristo`
## ==========================


import
  std/times,
  eth/[common, trie/nibbles],
  results,
  ./aristo_desc/desc_backend,
  ./aristo_init/memory_db,
  "."/[aristo_delete, aristo_desc, aristo_fetch, aristo_get, aristo_hashify,
       aristo_hike, aristo_init, aristo_merge, aristo_path, aristo_profile,
       aristo_serialise, aristo_tx, aristo_vid]

export
  AristoDbProfListRef

const
  AutoValidateApiHooks = defined(release).not
    ## No validatinon needed for production suite.

  AristoPersistentBackendOk = AutoValidateApiHooks # and false
    ## Set true for persistent backend profiling (which needs an extra
    ## link library.)

when AristoPersistentBackendOk:
  import ./aristo_init/rocks_db

# Annotation helper(s)
{.pragma: noRaise, gcsafe, raises: [].}

type
  AristoApiCommitFn* =
    proc(tx: AristoTxRef;
        ): Result[void,AristoError]
        {.noRaise.}
      ## Given a *top level* handle, this function accepts all database
      ## operations performed through this handle and merges it to the
      ## previous layer. The previous transaction is returned if there
      ## was any.

  AristoApiDeleteFn* =
    proc(db: AristoDbRef;
         root: VertexID;
         path: openArray[byte];
         accPath: PathID;
        ): Result[bool,(VertexID,AristoError)]
        {.noRaise.}
      ## Delete a leaf with path `path` starting at root `root`.
      ##
      ## For a `root` with `VertexID` greater than `LEAST_FREE_VID`, the
      ## sub-tree generated by `payload.root` is considered a storage trie
      ## linked to an account leaf referred to by a valid `accPath` (i.e.
      ## different from `VOID_PATH_ID`.) In that case, an account must
      ## exists. If there is payload of type `AccountData`, its `storageID`
      ## field must be unset or equal to the `root` vertex ID.
      ##
      ## The return code is `true` iff the trie has become empty.

  AristoApiDelTreeFn* =
    proc(db: AristoDbRef;
         root: VertexID;
         accPath: PathID;
        ): Result[void,(VertexID,AristoError)]
        {.noRaise.}
      ## Delete sub-trie below `root`. The maximum supported sub-tree size
      ## is `SUB_TREE_DISPOSAL_MAX`. Larger tries must be disposed by
      ## walk-deleting leaf nodes using `left()` or `right()` traversal
      ## functions.
      ##
      ## For a `root` argument greater than `LEAST_FREE_VID`, the sub-tree
      ## spanned by `root` is considered a storage trie linked to an account
      ## leaf referred to by a valid `accPath` (i.e. different from
      ## `VOID_PATH_ID`.) In that case, an account must exists. If there is
      ## payload of type `AccountData`, its `storageID` field must be unset
      ## or equal to the `hike.root` vertex ID.

  AristoApiFetchLastSavedStateFn* =
    proc(db: AristoDbRef
        ): Result[SavedState,AristoError]
        {.noRaise.}
      ## The function returns the state of the last saved state. This is a
      ## Merkle hash tag for vertex with ID 1 and a bespoke `uint64` identifier
      ## (may be interpreted as block number.)

  AristoApiFetchPayloadFn* =
    proc(db: AristoDbRef;
         root: VertexID;
         path: openArray[byte];
        ): Result[PayloadRef,(VertexID,AristoError)]
        {.noRaise.}
      ## Cascaded attempt to traverse the `Aristo Trie` and fetch the value
      ## of a leaf vertex. This function is complementary to `mergePayload()`.

  AristoApiFindTxFn* =
    proc(db: AristoDbRef;
         vid: VertexID;
         key: HashKey;
        ): Result[int,AristoError]
        {.noRaise.}
      ## Find the transaction where the vertex with ID `vid` exists and has
      ## the Merkle hash key `key`. If there is no transaction available,
      ## search in the filter and then in the backend.
      ##
      ## If the above procedure succeeds, an integer indicating the transaction
      ## level is returned:
      ##
      ## * `0` -- top level, current layer
      ## * `1`,`2`,`..` -- some transaction level further down the stack
      ## * `-1` -- the filter between transaction stack and database backend
      ## * `-2` -- the databse backend
      ##
      ## A successful return code might be used for the `forkTx()` call for
      ## creating a forked descriptor that provides the pair `(vid,key)`.
      ##

  AristoApiFinishFn* =
    proc(db: AristoDbRef;
         flush = false;
        ) {.noRaise.}
      ## Backend destructor. The argument `flush` indicates that a full
      ## database deletion is requested. If set `false` the outcome might
      ## differ depending on the type of backend (e.g. the `BackendMemory`
      ## backend will always flush on close.)
      ##
      ## In case of distributed descriptors accessing the same backend, all
      ## distributed descriptors will be destroyed.
      ##
      ## This distructor may be used on already *destructed* descriptors.

  AristoApiForgetFn* =
    proc(db: AristoDbRef;
        ): Result[void,AristoError]
        {.noRaise.}
      ## Destruct the non centre argument `db` descriptor (see comments on
      ## `reCentre()` for details.)
      ##
      ## A non centre descriptor should always be destructed after use (see
      ## also# comments on `fork()`.)

  AristoApiForkTxFn* =
    proc(db: AristoDbRef;
         backLevel: int;
         dontHashify = false;
        ): Result[AristoDbRef,AristoError]
        {.noRaise.}
    ## Fork a new descriptor obtained from parts of the argument database
    ## as described by arguments `db` and `backLevel`.
    ##
    ## If the argument `backLevel` is non-negative, the forked descriptor
    ## will provide the database view where the first `backLevel` transaction
    ## layers are stripped and the remaing layers are squashed into a single
    ## transaction.
    ##
    ## If `backLevel` is `-1`, a database descriptor with empty transaction
    ## layers will be provided where the `balancer` between database and
    ## transaction layers are kept in place.
    ##
    ## If `backLevel` is `-2`, a database descriptor with empty transaction
    ## layers will be provided without a `balancer`.
    ##
    ## The returned database descriptor will always have transaction level one.
    ## If there were no transactions that could be squashed, an empty
    ## transaction is added.
    ##
    ## If the arguent flag `dontHashify` is passed `true`, the forked descriptor
    ## will *NOT* be hashified right after construction.
    ##
    ## Use `aristo_desc.forget()` to clean up this descriptor.

  AristoApiGetKeyRcFn* =
    proc(db: AristoDbRef;
         vid: VertexID;
        ): Result[HashKey,AristoError]
        {.noRaise.}
      ## Cascaded attempt to fetch a Merkle hash from the cache layers or
      ## the backend (if available.)

  AristoApiHashifyFn* =
    proc(db: AristoDbRef;
        ): Result[void,(VertexID,AristoError)]
        {.noRaise.}
      ## Add keys to the  `Patricia Trie` so that it becomes a `Merkle
      ## Patricia Tree`.

  AristoApiHasPathFn* =
    proc(db: AristoDbRef;
         root: VertexID;
         path: openArray[byte];
        ): Result[bool,(VertexID,AristoError)]
        {.noRaise.}
      ## Variant of `fetchPayload()` without returning data. It returns
      ## `true` iff the database `db` contains a leaf item with the argument
      ## path.

  AristoApiHikeUpFn* =
    proc(path: NibblesSeq;
         root: VertexID;
         db: AristoDbRef;
        ): Result[Hike,(VertexID,AristoError,Hike)]
        {.noRaise.}
      ## For the argument `path`, find and return the logest possible path
      ## in the argument database `db`.

  AristoApiIsTopFn* =
    proc(tx: AristoTxRef;
        ): bool
        {.noRaise.}
      ## Getter, returns `true` if the argument `tx` referes to the current
      ## top level transaction.

  AristoApiLevelFn* =
    proc(db: AristoDbRef;
        ): int
        {.noRaise.}
      ## Getter, non-negative nesting level (i.e. number of pending
      ## transactions)

  AristoApiNForkedFn* =
    proc(db: AristoDbRef;
        ): int
        {.noRaise.}
      ## Returns the number of non centre descriptors (see comments on
      ## `reCentre()` for details.) This function is a fast version of
      ## `db.forked.toSeq.len`.

  AristoApiMergeFn* =
    proc(db: AristoDbRef;
         root: VertexID;
         path: openArray[byte];
         data: openArray[byte];
         accPath: PathID;
        ): Result[bool,AristoError]
        {.noRaise.}
      ## Veriant of `mergePayload()` where the `data` argument will be
      ## converted to a `RawBlob` type `PayloadRef` value.

  AristoApiMergePayloadFn* =
    proc(db: AristoDbRef;
         root: VertexID;
         path: openArray[byte];
         payload: PayloadRef;
         accPath = VOID_PATH_ID;
        ): Result[bool,AristoError]
        {.noRaise.}
      ## Merge the argument key-value-pair `(path,payload)` into the top level
      ## vertex table of the database `db`.
      ##
      ## For a `root` argument with `VertexID` greater than `LEAST_FREE_VID`,
      ## the sub-tree generated by `payload.root` is considered a storage trie
      ## linked to an account leaf referred to by a valid `accPath` (i.e.
      ## different from `VOID_PATH_ID`.) In that case, an account must exists.
      ## If there is payload of type `AccountData`, its `storageID` field must
      ## be unset or equal to the `payload.root` vertex ID.

  AristoApiPathAsBlobFn* =
    proc(tag: PathID;
        ): Blob
        {.noRaise.}
      ## Converts the `tag` argument to a sequence of an even number of
      ## nibbles represented by a `Blob`. If the argument `tag` represents
      ## an odd number of nibbles, a zero nibble is appendend.
      ##
      ## This function is useful only if there is a tacit agreement that all
      ## paths used to index database leaf values can be represented as
      ## `Blob`, i.e. `PathID` type paths with an even number of nibbles.

  AristoApiPersistFn* =
    proc(db: AristoDbRef;
         nxtSid = 0u64;
         chunkedMpt = false;
        ): Result[void,AristoError]
        {.noRaise.}
      ## Persistently store data onto backend database. If the system is
      ## running without a database backend, the function returns immediately
      ## with an error. The same happens if there is a pending transaction.
      ##
      ## The function merges all staged data from the top layer cache onto the
      ## backend stage area. After that, the top layer cache is cleared.
      ##
      ## Finally, the staged data are merged into the physical backend
      ## database and the staged data area is cleared.
      ##
      ## The argument `nxtSid` will be the ID for the next saved state record.
      ##
      ## Staging the top layer cache might fail with a partial MPT when it is
      ## set up from partial MPT chunks as it happens with `snap` sync
      ## processing. In this case, the `chunkedMpt` argument must be set
      ## `true` (see alse `fwdFilter()`.)

  AristoApiReCentreFn* =
    proc(db: AristoDbRef;
        ) {.noRaise.}
      ## Re-focus the `db` argument descriptor so that it becomes the centre.
      ## Nothing is done if the `db` descriptor is the centre, already.
      ##
      ## With several descriptors accessing the same backend database there is
      ## a single one that has write permission for the backend (regardless
      ## whether there is a backend, at all.) The descriptor entity with write
      ## permission is called *the centre*.
      ##
      ## After invoking `reCentre()`, the argument database `db` can only be
      ## destructed by `finish()` which also destructs all other descriptors
      ## accessing the same backend database. Descriptors where `isCentre()`
      ## returns `false` must be single destructed with `forget()`.

  AristoApiRollbackFn* =
    proc(tx: AristoTxRef;
        ): Result[void,AristoError]
        {.noRaise.}
      ## Given a *top level* handle, this function discards all database
      ## operations performed for this transactio. The previous transaction
      ## is returned if there was any.

  AristoApiSerialiseFn* =
    proc(db: AristoDbRef;
         pyl: PayloadRef;
        ): Result[Blob,(VertexID,AristoError)]
        {.noRaise.}
      ## Encode the data payload of the argument `pyl` as RLP `Blob` if
      ## it is of account type, otherwise pass the data as is.

  AristoApiTxBeginFn* =
    proc(db: AristoDbRef
        ): Result[AristoTxRef,AristoError]
        {.noRaise.}
      ## Starts a new transaction.
      ##
      ## Example:
      ## ::
      ##   proc doSomething(db: AristoDbRef) =
      ##     let tx = db.begin
      ##     defer: tx.rollback()
      ##     ... continue using db ...
      ##     tx.commit()

  AristoApiTxTopFn* =
    proc(db: AristoDbRef;
        ): Result[AristoTxRef,AristoError]
        {.noRaise.}
      ## Getter, returns top level transaction if there is any.

  AristoApiVidFetchFn* =
    proc(db: AristoDbRef;
         pristine = false;
        ): VertexID
        {.noRaise.}
      ## Recycle or create a new `VertexID`. Reusable vertex *ID*s are kept
      ## in a list where the top entry *ID* has the property that any other
      ## *ID* larger is also not used on the database.
      ##
      ## The function prefers to return recycled vertex *ID*s if there are
      ## any. When the argument `pristine` is set `true`, the function
      ## guarantees to return a non-recycled, brand new vertex *ID* which
      ## is the preferred mode when creating leaf vertices.

  AristoApiVidDisposeFn* =
    proc(db: AristoDbRef;
         vid: VertexID;
        ) {.noRaise.}
      ## Recycle the argument `vtxID` which is useful after deleting entries
      ## from the vertex table to prevent the `VertexID` type key values
      ## small.

  AristoApiRef* = ref AristoApiObj
  AristoApiObj* = object of RootObj
    ## Useful set of `Aristo` fuctions that can be filtered, stacked etc.
    commit*: AristoApiCommitFn
    delete*: AristoApiDeleteFn
    delTree*: AristoApiDelTreeFn
    fetchLastSavedState*: AristoApiFetchLastSavedStateFn
    fetchPayload*: AristoApiFetchPayloadFn
    findTx*: AristoApiFindTxFn
    finish*: AristoApiFinishFn
    forget*: AristoApiForgetFn
    forkTx*: AristoApiForkTxFn
    getKeyRc*: AristoApiGetKeyRcFn
    hashify*: AristoApiHashifyFn
    hasPath*: AristoApiHasPathFn
    hikeUp*: AristoApiHikeUpFn
    isTop*: AristoApiIsTopFn
    level*: AristoApiLevelFn
    nForked*: AristoApiNForkedFn
    merge*: AristoApiMergeFn
    mergePayload*: AristoApiMergePayloadFn
    pathAsBlob*: AristoApiPathAsBlobFn
    persist*: AristoApiPersistFn
    reCentre*: AristoApiReCentreFn
    rollback*: AristoApiRollbackFn
    serialise*: AristoApiSerialiseFn
    txBegin*: AristoApiTxBeginFn
    txTop*: AristoApiTxTopFn
    vidFetch*: AristoApiVidFetchFn
    vidDispose*: AristoApiVidDisposeFn


  AristoApiProfNames* = enum
    ## Index/name mapping for profile slots
    AristoApiProfTotal          = "total"

    AristoApiProfCommitFn              = "commit"
    AristoApiProfDeleteFn              = "delete"
    AristoApiProfDelTreeFn             = "delTree"
    AristoApiProfFetchLastSavedStateFn = "fetchPayload"
    AristoApiProfFetchPayloadFn        = "fetchPayload"
    AristoApiProfFindTxFn              = "findTx"
    AristoApiProfFinishFn              = "finish"
    AristoApiProfForgetFn              = "forget"
    AristoApiProfForkTxFn              = "forkTx"
    AristoApiProfGetKeyRcFn            = "getKeyRc"
    AristoApiProfHashifyFn             = "hashify"
    AristoApiProfHasPathFn             = "hasPath"
    AristoApiProfHikeUpFn              = "hikeUp"
    AristoApiProfIsTopFn               = "isTop"
    AristoApiProfLevelFn               = "level"
    AristoApiProfNForkedFn             = "nForked"
    AristoApiProfMergeFn               = "merge"
    AristoApiProfMergePayloadFn        = "mergePayload"
    AristoApiProfPathAsBlobFn          = "pathAsBlob"
    AristoApiProfPersistFn             = "persist"
    AristoApiProfReCentreFn            = "reCentre"
    AristoApiProfRollbackFn            = "rollback"
    AristoApiProfSerialiseFn           = "serialise"
    AristoApiProfTxBeginFn             = "txBegin"
    AristoApiProfTxTopFn               = "txTop"
    AristoApiProfVidFetchFn            = "vidFetch"
    AristoApiProfVidDisposeFn          = "vidDispose"

    AristoApiProfBeGetVtxFn            = "be/getVtx"
    AristoApiProfBeGetKeyFn            = "be/getKey"
    AristoApiProfBeGetIdgFn            = "be/getIfg"
    AristoApiProfBeGetLstFn            = "be/getLst"
    AristoApiProfBePutVtxFn            = "be/putVtx"
    AristoApiProfBePutKeyFn            = "be/putKey"
    AristoApiProfBePutIdgFn            = "be/putIdg"
    AristoApiProfBePutLstFn            = "be/putLst"
    AristoApiProfBePutEndFn            = "be/putEnd"

  AristoApiProfRef* = ref object of AristoApiRef
    ## Profiling API extension of `AristoApiObj`
    data*: AristoDbProfListRef
    be*: BackendRef

# ------------------------------------------------------------------------------
# Private helpers
# ------------------------------------------------------------------------------

when AutoValidateApiHooks:
  proc validate(api: AristoApiObj|AristoApiRef) =
    doAssert not api.commit.isNil
    doAssert not api.delete.isNil
    doAssert not api.delTree.isNil
    doAssert not api.fetchLastSavedState.isNil
    doAssert not api.fetchPayload.isNil
    doAssert not api.findTx.isNil
    doAssert not api.finish.isNil
    doAssert not api.forget.isNil
    doAssert not api.forkTx.isNil
    doAssert not api.getKeyRc.isNil
    doAssert not api.hashify.isNil
    doAssert not api.hasPath.isNil
    doAssert not api.hikeUp.isNil
    doAssert not api.isTop.isNil
    doAssert not api.level.isNil
    doAssert not api.nForked.isNil
    doAssert not api.merge.isNil
    doAssert not api.mergePayload.isNil
    doAssert not api.pathAsBlob.isNil
    doAssert not api.persist.isNil
    doAssert not api.reCentre.isNil
    doAssert not api.rollback.isNil
    doAssert not api.serialise.isNil
    doAssert not api.txBegin.isNil
    doAssert not api.txTop.isNil
    doAssert not api.vidFetch.isNil
    doAssert not api.vidDispose.isNil

  proc validate(prf: AristoApiProfRef) =
    prf.AristoApiRef.validate
    doAssert not prf.data.isNil

proc dup(be: BackendRef): BackendRef =
  case be.kind:
  of BackendMemory:
    return MemBackendRef(be).dup

  of BackendRocksDB:
    when AristoPersistentBackendOk:
      return RdbBackendRef(be).dup

  of BackendVoid:
    discard

# ------------------------------------------------------------------------------
# Public API constuctors
# ------------------------------------------------------------------------------

func init*(api: var AristoApiObj) =
  ## Initialise an `api` argument descriptor
  ##
  when AutoValidateApiHooks:
    api.reset
  api.commit = commit
  api.delete = delete
  api.delTree = delTree
  api.fetchLastSavedState = fetchLastSavedState
  api.fetchPayload = fetchPayload
  api.findTx = findTx
  api.finish = finish
  api.forget = forget
  api.forkTx = forkTx
  api.getKeyRc = getKeyRc
  api.hashify = hashify
  api.hasPath = hasPath
  api.hikeUp = hikeUp
  api.isTop = isTop 
  api.level = level
  api.nForked = nForked
  api.merge = merge
  api.mergePayload = mergePayload
  api.pathAsBlob = pathAsBlob
  api.persist = persist
  api.reCentre = reCentre
  api.rollback = rollback
  api.serialise = serialise
  api.txBegin = txBegin
  api.txTop = txTop
  api.vidFetch = vidFetch
  api.vidDispose = vidDispose
  when AutoValidateApiHooks:
    api.validate

func init*(T: type AristoApiRef): T =
  new result
  result[].init()

func dup*(api: AristoApiRef): AristoApiRef =
  result = AristoApiRef(
    commit:              api.commit,
    delete:              api.delete,
    delTree:             api.delTree,
    fetchLastSavedState: api.fetchLastSavedState,
    fetchPayload:        api.fetchPayload,
    findTx:              api.findTx,
    finish:              api.finish,
    forget:              api.forget,
    forkTx:              api.forkTx,
    getKeyRc:            api.getKeyRc,
    hashify:             api.hashify,
    hasPath:             api.hasPath,
    hikeUp:              api.hikeUp,
    isTop:               api.isTop,
    level:               api.level,
    nForked:             api.nForked,
    merge:               api.merge,
    mergePayload:        api.mergePayload,
    pathAsBlob:          api.pathAsBlob,
    persist:             api.persist,
    reCentre:            api.reCentre,
    rollback:            api.rollback,
    serialise:           api.serialise,
    txBegin:             api.txBegin,
    txTop:               api.txTop,
    vidFetch:            api.vidFetch,
    vidDispose:          api.vidDispose)
  when AutoValidateApiHooks:
    api.validate

# ------------------------------------------------------------------------------
# Public profile API constuctor
# ------------------------------------------------------------------------------

func init*(
    T: type AristoApiProfRef;
    api: AristoApiRef;
    be = BackendRef(nil);
      ): T =
  ## This constructor creates a profiling API descriptor to be derived from
  ## an initialised `api` argument descriptor. For profiling the DB backend,
  ## the field `.be` of the result descriptor must be assigned to the
  ## `.backend` field of the `AristoDbRef` descriptor.
  ##
  ## The argument desctiptors `api` and `be` will not be modified and can be
  ## used to restore the previous set up.
  ##
  let
    data = AristoDbProfListRef(
      list: newSeq[AristoDbProfData](1 + high(AristoApiProfNames).ord))
    profApi = T(data: data)

  template profileRunner(n: AristoApiProfNames, code: untyped): untyped =
    let start = getTime()
    code
    data.update(n.ord, getTime() - start)

  profApi.commit =
    proc(a: AristoTxRef): auto =
      AristoApiProfCommitFn.profileRunner:
        result = api.commit(a)

  profApi.delete =
    proc(a: AristoDbRef; b: VertexID; c: openArray[byte]; d: PathID): auto =
      AristoApiProfDeleteFn.profileRunner:
        result = api.delete(a, b, c, d)

  profApi.delTree =
    proc(a: AristoDbRef; b: VertexID; c: PathID): auto =
      AristoApiProfDelTreeFn.profileRunner:
        result = api.delTree(a, b, c)

  profApi.fetchLastSavedState =
    proc(a: AristoDbRef): auto =
      AristoApiProfFetchLastSavedStateFn.profileRunner:
        result = api.fetchLastSavedState(a)

  profApi.fetchPayload =
    proc(a: AristoDbRef; b: VertexID; c: openArray[byte]): auto =
      AristoApiProfFetchPayloadFn.profileRunner:
        result = api.fetchPayload(a, b, c)

  profApi.findTx =
    proc(a: AristoDbRef; b: VertexID; c: HashKey): auto =
      AristoApiProfFindTxFn.profileRunner:
        result = api.findTx(a, b, c)

  profApi.finish =
    proc(a: AristoDbRef; b = false) =
      AristoApiProfFinishFn.profileRunner:
        api.finish(a, b)

  profApi.forget =
    proc(a: AristoDbRef): auto =
      AristoApiProfForgetFn.profileRunner:
        result = api.forget(a)

  profApi.forkTx =
    proc(a: AristoDbRef; b: int; c = false): auto =
      AristoApiProfForkTxFn.profileRunner:
        result = api.forkTx(a, b, c)

  profApi.getKeyRc =
    proc(a: AristoDbRef; b: VertexID): auto =
      AristoApiProfGetKeyRcFn.profileRunner:
        result = api.getKeyRc(a, b)

  profApi.hashify =
    proc(a: AristoDbRef): auto =
      AristoApiProfHashifyFn.profileRunner:
        result = api.hashify(a)

  profApi.hasPath =
    proc(a: AristoDbRef; b: VertexID; c: openArray[byte]): auto =
      AristoApiProfHasPathFn.profileRunner:
        result = api.hasPath(a, b, c)

  profApi.hikeUp =
    proc(a: NibblesSeq; b: VertexID; c: AristoDbRef): auto =
      AristoApiProfHikeUpFn.profileRunner:
        result = api.hikeUp(a, b, c)

  profApi.isTop =
    proc(a: AristoTxRef): auto =
      AristoApiProfIsTopFn.profileRunner:
        result = api.isTop(a)

  profApi.level =
    proc(a: AristoDbRef): auto =
       AristoApiProfLevelFn.profileRunner:
         result = api.level(a)

  profApi.nForked =
    proc(a: AristoDbRef): auto =
      AristoApiProfNForkedFn.profileRunner:
         result = api.nForked(a)

  profApi.merge =
    proc(a: AristoDbRef; b: VertexID; c,d: openArray[byte]; e: PathID): auto =
      AristoApiProfMergeFn.profileRunner:
         result = api.merge(a, b, c, d ,e)

  profApi.mergePayload =
    proc(a: AristoDbRef; b: VertexID; c: openArray[byte]; d: PayloadRef;
         e = VOID_PATH_ID): auto =
      AristoApiProfMergePayloadFn.profileRunner:
        result = api.mergePayload(a, b, c, d ,e)

  profApi.pathAsBlob =
    proc(a: PathID): auto =
      AristoApiProfPathAsBlobFn.profileRunner:
        result = api.pathAsBlob(a)

  profApi.persist =
    proc(a: AristoDbRef; b = 0u64; c = false): auto =
       AristoApiProfPersistFn.profileRunner:
        result = api.persist(a, b, c)

  profApi.reCentre =
    proc(a: AristoDbRef) =
      AristoApiProfReCentreFn.profileRunner:
        api.reCentre(a)

  profApi.rollback =
    proc(a: AristoTxRef): auto =
      AristoApiProfRollbackFn.profileRunner:
        result = api.rollback(a)

  profApi.serialise =
    proc(a: AristoDbRef; b: PayloadRef): auto =
      AristoApiProfSerialiseFn.profileRunner:
        result = api.serialise(a, b)

  profApi.txBegin =
    proc(a: AristoDbRef): auto =
       AristoApiProfTxBeginFn.profileRunner:
        result = api.txBegin(a)

  profApi.txTop =
    proc(a: AristoDbRef): auto =
      AristoApiProfTxTopFn.profileRunner:
        result = api.txTop(a)

  profApi.vidFetch =
    proc(a: AristoDbRef; b = false): auto =
      AristoApiProfVidFetchFn.profileRunner:
        result = api.vidFetch(a, b)

  profApi.vidDispose =
    proc(a: AristoDbRef;b: VertexID) =
      AristoApiProfVidDisposeFn.profileRunner:
        api.vidDispose(a, b)

  let beDup = be.dup()
  if beDup.isNil:
    profApi.be = be

  else:
    beDup.getVtxFn =
      proc(a: VertexID): auto =
        AristoApiProfBeGetVtxFn.profileRunner:
          result = be.getVtxFn(a)
    data.list[AristoApiProfBeGetVtxFn.ord].masked = true

    beDup.getKeyFn =
      proc(a: VertexID): auto =
        AristoApiProfBeGetKeyFn.profileRunner:
          result = be.getKeyFn(a)
    data.list[AristoApiProfBeGetKeyFn.ord].masked = true

    beDup.getIdgFn =
      proc(): auto =
        AristoApiProfBeGetIdgFn.profileRunner:
          result = be.getIdgFn()
    data.list[AristoApiProfBeGetIdgFn.ord].masked = true

    beDup.getLstFn =
      proc(): auto =
        AristoApiProfBeGetLstFn.profileRunner:
          result = be.getLstFn()
    data.list[AristoApiProfBeGetLstFn.ord].masked = true

    beDup.putVtxFn =
      proc(a: PutHdlRef; b: openArray[(VertexID,VertexRef)]) =
        AristoApiProfBePutVtxFn.profileRunner:
          be.putVtxFn(a,b)
    data.list[AristoApiProfBePutVtxFn.ord].masked = true

    beDup.putKeyFn =
      proc(a: PutHdlRef; b: openArray[(VertexID,HashKey)]) =
        AristoApiProfBePutKeyFn.profileRunner:
          be.putKeyFn(a,b)
    data.list[AristoApiProfBePutKeyFn.ord].masked = true

    beDup.putIdgFn =
      proc(a: PutHdlRef; b: openArray[VertexID]) =
        AristoApiProfBePutIdgFn.profileRunner:
          be.putIdgFn(a,b)
    data.list[AristoApiProfBePutIdgFn.ord].masked = true

    beDup.putLstFn =
      proc(a: PutHdlRef; b: SavedState) =
        AristoApiProfBePutLstFn.profileRunner:
          be.putLstFn(a,b)
    data.list[AristoApiProfBePutLstFn.ord].masked = true

    beDup.putEndFn =
      proc(a: PutHdlRef): auto =
        AristoApiProfBePutEndFn.profileRunner:
          result = be.putEndFn(a)
    data.list[AristoApiProfBePutEndFn.ord].masked = true

    profApi.be = beDup

  when AutoValidateApiHooks:
    profApi.validate

  profApi

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------
