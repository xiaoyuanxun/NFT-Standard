import Account "../../Module/Account";
import AccountTypes "../../Module/AccountTypes";
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Cycles "mo:base/ExperimentalCycles";
import Debug "mo:base/Debug";
import Error "mo:base/Error";
import Hash "mo:base/Hash";
import HashMap "mo:base/HashMap";
import Int "mo:base/Int";
import Interface "../../Module/Interface";
import Iter "mo:base/Iter";
import List "mo:base/List";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import Prelude "mo:base/Prelude";
import Prim "mo:⛔";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import SHA256 "../../Module/SHA256";
import SM "mo:base/ExperimentalStableMemory";
import Text "mo:base/Text";
import Time "mo:base/Time";
import TimeBase "mo:base/Time";
import TrieMap "mo:base/TrieMap";
import TrieSet "mo:base/TrieSet";
import Types "Types";

// 调用storage记得删除//xun
// 此处仅为了方便不编译报错
shared(msg) actor class NFToken(
    _logo: Text,
    _name: Text, 
    _symbol: Text,
    _desc: Text,
    _owner: Principal
    ) = this {

    type Metadata = Types.Metadata;
    type Location = Types.Location;
    type Attribute = Types.Attribute;
    type TokenMetadata = Types.TokenMetadata;
    type Record = Types.Record;
    type TxRecord = Types.TxRecord;
    type Operation = Types.Operation;
    type TokenInfo = Types.TokenInfo;
    type TokenInfoExt = Types.TokenInfoExt;
    type UserInfo = Types.UserInfo;
    type UserInfoExt = Types.UserInfoExt;
    type LedgerActor = Interface.LedgerActor;
    type AccountIdentifier = AccountTypes.AccountIdentifier;
    type SendArgs = AccountTypes.SendArgs;
    public type Error = {
        #Unauthorized;
        #TokenNotExist;
        #InvalidOperator;
    };
    public type TxReceipt = Result.Result<Nat, Error>;
    public type MintResult = Result.Result<(Nat, Nat), Error>; // token index, txid

    private stable var logo_ : Text = _logo; // base64 encoded image
    private stable var name_ : Text = _name;
    private stable var symbol_ : Text = _symbol;
    private stable var desc_ : Text = _desc;
    private stable var owner_: Principal = _owner;
    private stable var totalSupply_: Nat = 0;
    private stable var blackhole: Principal = Principal.fromText("aaaaa-aa");
    private stable let ICPFEE : Nat64 = 10000; // 0.0001 ICP
    private stable var tokensEntries : [(Nat, TokenInfo)] = [];
    private stable var usersEntries : [(Principal, UserInfo)] = [];
    private var tokens = HashMap.HashMap<Nat, TokenInfo>(1, Nat.equal, Hash.hash); // suply_index -> tokeninfo
    private var users = HashMap.HashMap<Principal, UserInfo>(1, Principal.equal, Principal.hash);
    private stable var txs: [TxRecord] = [];
    private stable var txIndex: Nat = 0;

    private func addTxRecord(
        caller: Principal, op: Operation, tokenIndex: ?Nat,
        from: Record, to: Record, timestamp: Time.Time
    ): Nat {
        let record: TxRecord = {
            caller = caller;
            op = op;
            index = txIndex;
            tokenIndex = tokenIndex;
            from = from;
            to = to;
            timestamp = timestamp;
        };
        txs := Array.append(txs, [record]);
        txIndex += 1;
        return txIndex - 1;
    };

    private func _unwrap<T>(x : ?T) : T =
    switch x {
      case null { Prelude.unreachable() };
      case (?x_) { x_ };
    };

    private func _exists(tokenId: Nat) : Bool {
        switch (tokens.get(tokenId)) {
            case (?info) { return true; };
            case _ { return false; };
        }
    };

    private func _ownerOf(tokenId: Nat) : ?Principal {
        switch (tokens.get(tokenId)) {
            case (?info) { return ?info.owner; };
            case (_) { return null; };
        }
    };

    private func _isOwner(who: Principal, tokenId: Nat) : Bool {
        switch (tokens.get(tokenId)) {
            case (?info) { return info.owner == who; };
            case _ { return false; };
        };
    };

    private func _isApproved(who: Principal, tokenId: Nat) : Bool {
        switch (tokens.get(tokenId)) {
            case (?info) { return info.operator == ?who; };
            case _ { return false; };
        }
    };
    
    private func _balanceOf(who: Principal) : Nat {
        switch (users.get(who)) {
            case (?user) { return TrieSet.size(user.tokens); };
            case (_) { return 0; };
        }
    };

    private func _newUser() : UserInfo {
        {
            var operators = TrieSet.empty<Principal>();
            var allowedBy = TrieSet.empty<Principal>();
            var allowedTokens = TrieSet.empty<Nat>();
            var tokens = TrieSet.empty<Nat>();
        }
    };

    private func _tokenInfotoExt(info: TokenInfo) : TokenInfoExt {
        return {
            index = info.index;
            owner = info.owner;
            metadata = info.metadata;
            timestamp = info.timestamp;
            operator = info.operator;
        };
    };

    private func _userInfotoExt(info: UserInfo) : UserInfoExt {
        return {
            operators = TrieSet.toArray(info.operators);
            allowedBy = TrieSet.toArray(info.allowedBy);
            allowedTokens = TrieSet.toArray(info.allowedTokens);
            tokens = TrieSet.toArray(info.tokens);
        };
    };

    private func _isApprovedOrOwner(spender: Principal, tokenId: Nat) : Bool {
        switch (_ownerOf(tokenId)) {
            case (?owner) {
                return spender == owner or _isApproved(spender, tokenId) or _isApprovedForAll(owner, spender);
            };
            case _ {
                return false;
            };
        };        
    };

    private func _getApproved(tokenId: Nat) : ?Principal {
        switch (tokens.get(tokenId)) {
            case (?info) {
                return info.operator;
            };
            case (_) {
                return null;
            };
        }
    };

    private func _isApprovedForAll(owner: Principal, operator: Principal) : Bool {
        switch (users.get(owner)) {
            case (?user) {
                return TrieSet.mem(user.operators, operator, Principal.hash(operator), Principal.equal);
            };
            case _ { return false; };
        };
    };

    private func _addTokenTo(to: Principal, tokenId: Nat) { //将token放到用户的set中
        switch(users.get(to)) {
            case (?user) {
                user.tokens := TrieSet.put(user.tokens, tokenId, Hash.hash(tokenId), Nat.equal);
                users.put(to, user);
            };
            case _ {
                let user = _newUser();
                user.tokens := TrieSet.put(user.tokens, tokenId, Hash.hash(tokenId), Nat.equal);
                users.put(to, user);
            };
        }
    }; 

    private func _removeTokenFrom(owner: Principal, tokenId: Nat) {
        assert(_exists(tokenId) and _isOwner(owner, tokenId));
        switch(users.get(owner)) {
            case (?user) {
                user.tokens := TrieSet.delete(user.tokens, tokenId, Hash.hash(tokenId), Nat.equal);
                users.put(owner, user);
            };
            case _ {
                assert(false);
            };
        }
    };
   
    private func _clearApproval(owner: Principal, tokenId: Nat) {
        assert(_exists(tokenId) and _isOwner(owner, tokenId));
        switch (tokens.get(tokenId)) {
            case (?info) {
                if (info.operator != null) {
                    let op = _unwrap(info.operator);
                    let opInfo = _unwrap(users.get(op));
                    opInfo.allowedTokens := TrieSet.delete(opInfo.allowedTokens, tokenId, Hash.hash(tokenId), Nat.equal);
                    users.put(op, opInfo);
                    info.operator := null;
                    tokens.put(tokenId, info);
                }
            };
            case _ {
                assert(false);
            };
        }
    };  

    private func _transfer(to: Principal, tokenId: Nat) {
        assert(_exists(tokenId));
        switch(tokens.get(tokenId)) {
            case (?info) {
                _removeTokenFrom(info.owner, tokenId);
                _addTokenTo(to, tokenId);
                info.owner := to;
                tokens.put(tokenId, info);
            };
            case (_) {
                assert(false);
            };
        };
    };

    private func _burn(owner: Principal, tokenId: Nat) {
        _clearApproval(owner, tokenId);
        _transfer(blackhole, tokenId);
    };
/*
    public shared(msg) func send(amount: Nat64, to: AccountIdentifier): async Bool {
        if(msg.caller != owner_ ) { return false; };
        let ledger: LedgerActor = actor("ryjl3-tyaaa-aaaaa-aaaba-cai");
        let now = Nat64.fromIntWrap(TimeBase.now());
        let to_ = Account.accountIdentifierToBlob(to);
        let args: SendArgs = {
            memo = 1: Nat64;
            amount = { e8s = amount; };
            created_at_time = ?{ timestamp_nanos = now; };
            from_subaccount = null;
            to = to_;
            fee = { e8s = ICPFEE; };
        };
        ignore await ledger.send_dfx(args);
        return true;
    };*/

    // public update calls
    public shared(msg) func mint(to: Principal, metadata: ?TokenMetadata): async MintResult {
        if(msg.caller != owner_) {
            return #err(#Unauthorized);
        };
        let token: TokenInfo = {
            index = totalSupply_;
            var owner = to;
            var metadata = metadata;
            var operator = null;
            timestamp = Time.now();
        };
        tokens.put(totalSupply_, token);
        _addTokenTo(to, totalSupply_);
        totalSupply_ += 1;
        let txid = addTxRecord(msg.caller, #mint(metadata), ?token.index, #user(blackhole), #user(to), Time.now());
        return #ok((token.index, txid));
    };

    public shared(msg) func batchMint(to: Principal, arr: [?TokenMetadata]): async MintResult {
        if(msg.caller != owner_) {
            return #err(#Unauthorized);
        };
        let startIndex = totalSupply_;
        for(metadata in Iter.fromArray(arr)) {
            let token: TokenInfo = {
                index = totalSupply_;
                var owner = to;
                var metadata = metadata;
                var operator = null;
                timestamp = Time.now();
            };
            tokens.put(totalSupply_, token);
            _addTokenTo(to, totalSupply_);
            totalSupply_ += 1;
            ignore addTxRecord(msg.caller, #mint(metadata), ?token.index, #user(blackhole), #user(to), Time.now());
        };
        return #ok((startIndex, txs.size() - arr.size()));
    };

    public shared(msg) func burn(tokenId: Nat): async TxReceipt {
        if(_exists(tokenId) == false) {
            return #err(#TokenNotExist)
        };
        if(_isOwner(msg.caller, tokenId) == false) {
            return #err(#Unauthorized);
        };
        _burn(msg.caller, tokenId); //not delete tokenId from tokens temporarily. (consider storage limited, it should be delete.)
        let txid = addTxRecord(msg.caller, #burn, ?tokenId, #user(msg.caller), #user(blackhole), Time.now());
        return #ok(txid);
    };

    public shared(msg) func setTokenMetadata(tokenId: Nat, new_metadata: TokenMetadata) : async TxReceipt {
        // only canister owner can set
        if(msg.caller != owner_) {
            return #err(#Unauthorized);
        };
        if(_exists(tokenId) == false) {
            return #err(#TokenNotExist)
        };
        let token = _unwrap(tokens.get(tokenId));
        let old_metadate = token.metadata;
        token.metadata := ?new_metadata;
        tokens.put(tokenId, token);
        let txid = addTxRecord(msg.caller, #setMetadata, ?token.index, #metadata(old_metadate), #metadata(?new_metadata), Time.now());
        return #ok(txid);
    };

    public shared(msg) func approve(tokenId: Nat, operator: Principal) : async TxReceipt {
        var owner: Principal = switch (_ownerOf(tokenId)) {
            case (?own) {
                own;
            };
            case (_) {
                return #err(#TokenNotExist)
            }
        };
        if(Principal.equal(msg.caller, owner) == false)
            if(_isApprovedForAll(owner, msg.caller) == false)
                return #err(#Unauthorized);
        if(owner == operator) {
            return #err(#InvalidOperator);
        };
        switch (tokens.get(tokenId)) {
            case (?info) {
                info.operator := ?operator;
                tokens.put(tokenId, info);
            };
            case _ {
                return #err(#TokenNotExist);
            };
        };
        switch (users.get(operator)) {
            case (?user) {
                user.allowedTokens := TrieSet.put(user.allowedTokens, tokenId, Hash.hash(tokenId), Nat.equal);
                users.put(operator, user);
            };
            case _ {
                let user = _newUser();
                user.allowedTokens := TrieSet.put(user.allowedTokens, tokenId, Hash.hash(tokenId), Nat.equal);
                users.put(operator, user);
            };
        };
        let txid = addTxRecord(msg.caller, #approve, ?tokenId, #user(msg.caller), #user(operator), Time.now());
        return #ok(txid);
    };

    public shared(msg) func setApprovalForAll(operator: Principal, value: Bool): async TxReceipt {
        if(msg.caller == operator) { //?
            return #err(#Unauthorized);
        };
        var txid = 0;
        if value {
            let caller = switch (users.get(msg.caller)) {
                case (?user) { user };
                case _ { _newUser() };
            };
            caller.operators := TrieSet.put(caller.operators, operator, Principal.hash(operator), Principal.equal);
            users.put(msg.caller, caller);
            let user = switch (users.get(operator)) {
                case (?user) { user };
                case _ { _newUser() };
            };
            user.allowedBy := TrieSet.put(user.allowedBy, msg.caller, Principal.hash(msg.caller), Principal.equal);
            users.put(operator, user);
            txid := addTxRecord(msg.caller, #approveAll, null, #user(msg.caller), #user(operator), Time.now());
        } else {
            switch (users.get(msg.caller)) {
                case (?user) {
                    user.operators := TrieSet.delete(user.operators, operator, Principal.hash(operator), Principal.equal);    
                    users.put(msg.caller, user);
                };
                case _ { };
            };
            switch (users.get(operator)) {
                case (?user) {
                    user.allowedBy := TrieSet.delete(user.allowedBy, msg.caller, Principal.hash(msg.caller), Principal.equal);    
                    users.put(operator, user);
                };
                case _ { };
            };
            txid := addTxRecord(msg.caller, #revokeAll, null, #user(msg.caller), #user(operator), Time.now());
        };
        return #ok(txid);
    };

    public shared(msg) func transfer(to: Principal, tokenId: Nat): async TxReceipt {
        var owner: Principal = switch (_ownerOf(tokenId)) {
            case (?own) {
                own;
            };
            case (_) {
                return #err(#TokenNotExist)
            }
        };
        if (owner != msg.caller) {
            return #err(#Unauthorized);
        };
        _transfer(to, tokenId);
        let txid = addTxRecord(msg.caller, #transfer, ?tokenId, #user(msg.caller), #user(to), Time.now());
        return #ok(txid);
    };

    public shared(msg) func transferFrom(from: Principal, to: Principal, tokenId: Nat): async TxReceipt {
        if(_exists(tokenId) == false) {
            return #err(#TokenNotExist)
        };
        if(_isApprovedOrOwner(msg.caller, tokenId) == false) {
            return #err(#Unauthorized);
        };
        _clearApproval(from, tokenId);
        _transfer(to, tokenId);
        let txid = addTxRecord(msg.caller, #transferFrom, ?tokenId, #user(from), #user(to), Time.now());
        return #ok(txid);
    };

    public shared(msg) func batchTransferFrom(from: Principal, to: Principal, tokenIds: [Nat]): async TxReceipt {
        var num: Nat = 0;
        label l for(tokenId in Iter.fromArray(tokenIds)) {
            if(_exists(tokenId) == false) {
                continue l;
            };
            if(_isApprovedOrOwner(msg.caller, tokenId) == false) {
                continue l;
            };
            _clearApproval(from, tokenId);
            _transfer(to, tokenId);
            num += 1;
            ignore addTxRecord(msg.caller, #transferFrom, ?tokenId, #user(from), #user(to), Time.now());
        };
        return #ok(txs.size() - num);
    };

    // public query function 
    public query func logo(): async Text {
        return logo_;
    };

    public query func name(): async Text {
        return name_;
    };

    public query func symbol(): async Text {
        return symbol_;
    };

    public query func desc(): async Text {
        return desc_;
    };

    public query func balanceOf(who: Principal): async Nat {
        return _balanceOf(who);
    };

    public query func totalSupply(): async Nat {
        return totalSupply_;
    };

    // get metadata about this NFT collection
    public query func getMetadata(): async Metadata {
        {
            logo = logo_;
            name = name_;
            symbol = symbol_;
            desc = desc_;
            totalSupply = totalSupply_;
            owner = owner_;
            cycles = Cycles.balance();
        }
    };

    public query func isApprovedForAll(owner: Principal, operator: Principal) : async Bool {
        return _isApprovedForAll(owner, operator);
    };

    public query func getOperator(tokenId: Nat) : async Principal {
        switch (_exists(tokenId)) {
            case true {
                switch (_getApproved(tokenId)) {
                    case (?who) {
                        return who;
                    };
                    case (_) {
                        return Principal.fromText("aaaaa-aa");
                    };
                }   
            };
            case (_) {
                throw Error.reject("token not exist")
            };
        }
    };

    public query func getUserInfo(who: Principal) : async UserInfoExt {
        switch (users.get(who)) {
            case (?user) {
                return _userInfotoExt(user)
            };
            case _ {
                throw Error.reject("unauthorized");
            };
        };        
    };

    public query func getUserTokens(owner: Principal) : async [TokenInfoExt] {
        let tokenIds = switch (users.get(owner)) {
            case (?user) {
                TrieSet.toArray(user.tokens)
            };
            case _ {
                []
            };
        };
        var ret: [TokenInfoExt] = [];
        for(id in Iter.fromArray(tokenIds)) {
            ret := Array.append(ret, [_tokenInfotoExt(_unwrap(tokens.get(id)))]);
        };
        return ret;
    };

    public query func ownerOf(tokenId: Nat): async Principal {
        switch (_ownerOf(tokenId)) {
            case (?owner) {
                return owner;
            };
            case _ {
                throw Error.reject("token not exist")
            };
        }
    };

    public query func getTokenInfo(tokenId: Nat) : async TokenInfoExt {
        switch(tokens.get(tokenId)){
            case(?tokeninfo) {
                return _tokenInfotoExt(tokeninfo);
            };
            case(_) {
                throw Error.reject("token not exist");
            };
        };
    };

    // Optional
    public query func getAllTokens() : async [TokenInfoExt] {
        Iter.toArray(Iter.map(tokens.entries(), func (i: (Nat, TokenInfo)): TokenInfoExt {_tokenInfotoExt(i.1)}))
    };

    // transaction history related
    public query func historySize(): async Nat {
        return txs.size();
    };

    public query func getTransaction(index: Nat): async TxRecord {
        return txs[index];
    };

    public query func getTransactions(start: Nat, limit: Nat): async [TxRecord] {
        var res: [TxRecord] = [];
        var i = start;
        while (i < start + limit and i < txs.size()) {
            res := Array.append(res, [txs[i]]);
            i += 1;
        };
        return res;
    };

    public query func getUserTransactionAmount(user: Principal): async Nat {
        var res: Nat = 0;
        for (i in txs.vals()) {
            if (i.caller == user or i.from == #user(user) or i.to == #user(user)) {
                res += 1;
            };
        };
        return res;
    };

    public query func getUserTransactions(user: Principal, start: Nat, limit: Nat): async [TxRecord] {
        var res: [TxRecord] = [];
        var idx = 0;
        label l for (i in txs.vals()) {
            if (i.caller == user or i.from == #user(user) or i.to == #user(user)) {
                if(idx < start) {
                    idx += 1;
                    continue l;
                };
                if(idx >= start + limit) {
                    break l;
                };
                res := Array.append<TxRecord>(res, [i]);
                idx += 1;
            };
        };
        return res;
    };

    // upgrade functions
    system func preupgrade() {
        usersEntries := Iter.toArray(users.entries());
        tokensEntries := Iter.toArray(tokens.entries());
    };

    system func postupgrade() {
        type TokenInfo = Types.TokenInfo;
        type UserInfo = Types.UserInfo;

        users := HashMap.fromIter<Principal, UserInfo>(usersEntries.vals(), 1, Principal.equal, Principal.hash);
        tokens := HashMap.fromIter<Nat, TokenInfo>(tokensEntries.vals(), 1, Nat.equal, Hash.hash);
        usersEntries := [];
        tokensEntries := [];
    };

//-------------storage----------------------------------------------------
    private type Asset = Types.Asset;
    private type AssetExt = Types.AssetExt;
    private type Chunk = Types.Chunk;
    private type PUT = Types.PUT;
    private type GET = Types.GET;
    private type State = Types.State;
    private type Extension = Types.FileExtension;
    private type BufferAsset = Types.BufferAsset;
    private type ThumbNail = Types.ThumbNail;
    private let cycle_limit = 20_000_000_000_000;
    private let MAX_PAGE_NUMBER : Nat32 = 65535;
    private let PAGE_SIZE = 65536; // Byte
    private let THRESHOLD = 4294901760; // 65535 * 65536
    private let MAX_UPDATE_SIZE = 1992295;
    private let MAX_QUERY_SIZE = 3144728; // 3M - 1KB
    private let UPGRADE_SLICE = 6000; // 暂定
    private var offset = 4; // [0, 65535*65536-1]
    private var buffer_canister_id = ""; // buffer canister id text
    private var thumbnail_map = TrieMap.TrieMap<Blob, ThumbNail>(Blob.equal, Blob.hash);
    private var assets = TrieMap.TrieMap<Blob, Asset>(Blob.equal, Blob.hash); // file_key ase map
    private var buffer = HashMap.HashMap<Blob, BufferAsset>(10, Blob.equal, Blob.hash);  

    public query({caller}) func canisterState() : async State {
        {
            head_size = Prim.rts_heap_size();
            memory_size = Prim.rts_memory_size();
            balance = Cycles.balance();
        }
    };

    public query({caller}) func cycleBalance() : async Nat {
        Cycles.balance()
    };

    public query({caller}) func avlSM() : async Nat {
        _avlSM()
    };

    public query({caller}) func getThumbnail(file_key : Blob) : async Result.Result<ThumbNail, Text> {
        switch(_getThumbnail(file_key)) {
            case(#ok(tb)) { return #ok(tb)};
            case(#err(info)) {return #err(info)};
        };
    };

    public query({caller}) func getAssetextkey(file_key : Blob) : async Result.Result<AssetExt, Text>{
        switch(_getAssetextkey(file_key)) {
            case(#ok(aseext)) { #ok(aseext) };
            case(#err(info)) { #err(info) };
        }
    };

    // data : [flag, offset + size - 1]
    public query({caller}) func get(
        g : GET
    ) : async Result.Result<[Blob], Text>{
        switch(assets.get(g.file_key)){
            case(null){ #err("wrong file_key") };
            case(?ase){
                // 安全检测
                if(g.flag > ase.page_field.size()){
                    #err("wrong flag")
                }else{
                    Debug.print("page field : " # debug_show(ase.page_field));
                    let field = ase.page_field[g.flag];
                    Debug.print("bucket get field : " # debug_show(field));
                    #ok(_getSM(field))
                }
            };
        }
    };

    public shared({caller}) func put(
        put : PUT
    ) : async Result.Result<AssetExt, Text>{
        switch(put) {
            case(#thumb_nail(tb)) {
                switch(assets.get(tb.file_key)){
                    case(?ase) { return #ok(_assetExt(ase, true)); };
                    case(null) {};
                };
                let thumb_nail : ThumbNail = {
                    image = tb.image;
                    file_extension = tb.file_extension;
                };
                return _putThumbnail(tb.file_key, thumb_nail);
            };
            case(#segment(seg)) {
                switch(assets.get(seg.file_key)){
                    case(?ase) { return #ok(_assetExt(ase, true)); };
                    case(null) {};
                };
                switch(_inspectSize(seg.chunk.data)){
                    case(#ok(size)){ _upload(seg.file_key, seg.chunk, seg.chunk_number, seg.file_extension, seg.order, size) };
                    case(#err(info)){ #err(info) }
                }
            };
        }
    };

    public shared({caller}) func preUpgrade() : async() {
        SM.storeNat32(0, Nat32.fromNat(offset));
    };

    public shared({caller}) func postUpgrade() : async() {
        offset := Nat32.toNat(SM.loadNat32(0));
    };

    public shared({caller}) func setBufferCanister(p : Text) : async (){
        buffer_canister_id := p;
    };

    public shared({caller}) func wallet_receive() : async Nat {
        Cycles.accept(Cycles.available())
    };

    private func _appendBuffer(buffer : [var (Nat, Nat)], arr : [var (Nat, Nat)]) : [var (Nat, Nat)]{
        switch(buffer.size(), arr.size()) {
            case (0, 0) { [var] };
            case (0, _) { arr };
            case (_, 0) { buffer };
            case (xsSize, ysSize) {
                let res = Array.init<(Nat, Nat)>(buffer.size() + arr.size(), (0, 0));
                var i = 0;
                for(e in buffer.vals()){
                    res[i] := buffer[i];
                    i += 1;
                };
                for(e in arr.vals()){
                    res[i] := arr[i - buffer.size()];
                    i += 1;
                };
                res
            };
        }
    };

    private func _getThumbnail(file_key : Blob) : Result.Result<ThumbNail, Text>{
        switch(thumbnail_map.get(file_key)){
            case null { #err("wrong file_key") };
            case(?tb){ #ok(tb) };
        }
    };

    private func _putThumbnail(file_key : Blob, thumb_nail : ThumbNail) : Result.Result<AssetExt, Text>{
        thumbnail_map.put(file_key, thumb_nail);
        return #ok(_assetExt({
                file_key = file_key;
                page_field = [[(0, 0)]];
                total_size = 0;
                file_extension = thumb_nail.file_extension;
            }, false));
    };

    private func _getAssetextkey(file_key : Blob) : Result.Result<AssetExt, Text>{
        switch(assets.get(file_key)){
            case null { #err("wrong file_key") };
            case(?ase){
                #ok(_assetExt(ase, true))  
            };
        }
    };

    // inspect file_name file_key exist or not
    private func _inspectSize(data : Blob) : Result.Result<Nat, Text>{
        var size = data.size();
        if(size <= _avlSM()){
            #ok(size)
        }else{
            #err("insufficient memory")
        }
    };

    private func _digest(pred : [var Nat8], nd : [Nat8], received : Nat){
        var i = received * 32;
        for(e in nd.vals()){
            pred[i] := e;
            i := i + 1;
        };
    };

    // wirte page field -> query page field
    private func _pageField(buffer_page_field : [(Nat, Nat)], total_size : Nat) : [[(Nat, Nat)]]{
        var arrSize = 0;
        if(total_size % MAX_QUERY_SIZE == 0){
            arrSize := total_size / MAX_QUERY_SIZE;
        }else{
            arrSize := total_size / MAX_QUERY_SIZE + 1;
        };
        var res = Array.init<[(Nat, Nat)]>(arrSize, []);
        var i : Nat = 0;
        var rowSize : Nat = 0;
        var pre_start : Nat = 0;
        var pre_size : Nat = 0;
        var buffer : [var (Nat, Nat)] = [var];
        // merge query page field
        for((start, size) in buffer_page_field.vals()){
            if(rowSize + size <= MAX_QUERY_SIZE){
                if(start != 0 and pre_start + pre_size == start){
                    let li : Nat = buffer.size() - 1;
                    buffer[li] := (pre_start, pre_size + size);
                }else{
                    buffer := _appendBuffer(buffer, [var (start, size)]);
                    pre_start := start;
                    pre_size := size;
                };
                rowSize += size;
            }else if(rowSize == MAX_QUERY_SIZE){
                res[i] := Array.freeze(buffer);
                i := i + 1;
                buffer := [var (start, size)];
                pre_start := start;
                pre_size := size;
                rowSize := size;
            }else{
                assert(MAX_QUERY_SIZE > rowSize);
                if(start != 0 and pre_start + pre_size == start){
                    let li : Nat = buffer.size() - 1;
                    buffer[li] := (pre_start, pre_size + MAX_QUERY_SIZE - rowSize);
                }else{
                    buffer := _appendBuffer(buffer, [var (start, MAX_QUERY_SIZE - rowSize)])
                };
                res[i] := Array.freeze(buffer);
                i += 1;
                buffer := [var (start + MAX_QUERY_SIZE - rowSize, size - (MAX_QUERY_SIZE - rowSize))];
                pre_start := start + MAX_QUERY_SIZE - rowSize;
                pre_size := size - (MAX_QUERY_SIZE - rowSize);
                rowSize := size + rowSize - MAX_QUERY_SIZE;
            };
        };
        res[i] := Array.freeze(buffer);
        Array.freeze<[(Nat, Nat)]>(res)
    };

    // available stable wasm memory
    private func _avlSM() : Nat{
        THRESHOLD - offset + 1
    };
    
    // return page field
    private func _putSM(data : Blob, size : Nat) : (Nat, Nat){

        // 看本页的内存还剩多少
        let page_left : Nat = if(offset == 4){
                ignore SM.grow(1);
                PAGE_SIZE - offset % PAGE_SIZE
            }else{
                PAGE_SIZE - offset % PAGE_SIZE
            };

        let res = (offset, size);

        // 如果够则记录到本页， 如果不够就grow
        if(size <= page_left){
            //本页够
            SM.storeBlob(Nat32.fromNat(offset), data);
            offset += data.size();
        }else {
            assert(SM.size() <= MAX_PAGE_NUMBER);
            ignore SM.grow(Nat32.fromNat((size - page_left) / PAGE_SIZE + 1));
            SM.storeBlob(Nat32.fromNat(offset), data);
            offset += data.size();
        };
        res
    };

    private func _getSM(field : [(Nat, Nat)]) : [Blob]{
        let res = Array.init<Blob>(field.size(), "" : Blob);
        var i = 0;
        for((start, size) in field.vals()){
            res[i] := SM.loadBlob(Nat32.fromNat(start), size);
            i := i + 1;
        };
        Array.freeze<Blob>(res)
    };

    private func _assetExt(ase : Asset, upload_status : Bool) : AssetExt{
        {
            bucket_id = Principal.fromActor(this);
            upload_status = upload_status;
            file_key = ase.file_key;
            total_size = ase.total_size;
            file_extension = ase.file_extension;
            need_query_times = ase.page_field.size();
        }
    };

    private func _key(digests : [Nat8]) : Blob {
        Blob.fromArray(SHA256.sha256(digests))
    };

    /**
    *	inspect file format and file size
    *	put file data into stable wasm memory
    *	put file ase into assets
    */
    private func _upload(file_key : Blob, chunk : Chunk, chunk_num : Nat, extension : Extension, order : Nat, size : Nat) : Result.Result<AssetExt, Text> {
        var size_ = size;
        var field = (0, 0);
        if (chunk_num == 1) {
            field := _putSM(chunk.data, size_);
            let ase = {
                file_key = _key(chunk.digest);
                total_size = size_;
                page_field = [[field]];
                file_extension = extension;
            };
            assets.put(ase.file_key, ase);
            Debug.print("final asset" # debug_show(ase));
            return #ok(_assetExt(ase, true));
        };
        switch(buffer.get(file_key)){
            case (null) {
                var digest = Array.init<Nat8>(chunk_num*32, 0);
                var page_field = Array.init<(Nat, Nat)>(chunk_num, (0,0));
                field := _putSM(chunk.data, size_);
                page_field[order] := field;
                _digest(digest, chunk.digest, order);
                let buffer_asset = {
                    digest = digest;
                    chunk_number = chunk_num;
                    var page_field = page_field;
                    var total_size = size_;
                    var received = 1;
                };
                buffer.put(file_key, buffer_asset);
                #ok(_assetExt(
                    {
                        file_key = file_key;
                        page_field = [Array.freeze<(Nat, Nat)>(page_field)];
                        total_size = size_;
                        file_extension = extension;
                    }, false
                ))
            };
            case (?a){
                if(a.received + 1 == a.chunk_number){
                    _digest(a.digest, chunk.digest, order);
                    a.received += 1;
                    field := _putSM(chunk.data, size_);
                    a.page_field[order] := field;
                    let total_size = a.total_size + size_;
                    let digest = Array.freeze(a.digest);
                    let page_field = Array.freeze(a.page_field);
                    let ase = {
                        file_key = _key(digest);
                        page_field = _pageField(page_field, total_size);
                        total_size = total_size;
                        file_extension = extension;
                    };
                    assets.put(ase.file_key, ase);
                    buffer.delete(file_key);
                    Debug.print("final asset" # debug_show(ase));
                    #ok(_assetExt(ase, true))
                }else{
                    _digest(a.digest, chunk.digest, order);
                    a.received += 1;
                    field := _putSM(chunk.data, size_);
                    a.page_field[order] := field;
                    a.total_size += size_;
                    #ok(_assetExt(
                        {
                            file_key = file_key;
                            page_field = [Array.freeze<(Nat, Nat)>(a.page_field)];
                            total_size = size_;
                            file_extension = extension;
                        }, false
                    ))
                }
            };
        }
    };

};

