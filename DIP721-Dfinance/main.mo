/**
 * Module     : main.mo
 * Copyright  : 2021 DFinance Team
 * License    : Apache 2.0 with LLVM Exception
 * Maintainer : DFinance Team <hello@dfinance.ai>
 * Stability  : Experimental
 */

import HashMap "mo:base/HashMap";
import Cycles "mo:base/ExperimentalCycles";
import Principal "mo:base/Principal";
import Error "mo:base/Error";
import Option "mo:base/Option";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Hash "mo:base/Hash";
import Text "mo:base/Text";
import List "mo:base/List";
import Time "mo:base/Time";
import Iter "mo:base/Iter";
import TrieSet "mo:base/TrieSet";
import Array "mo:base/Array";
import Result "mo:base/Result";
import Prelude "mo:base/Prelude";
import Debug "mo:base/Debug";
import Types "./types";

// 一个canister对应一个Collection
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

    private stable var tokensEntries : [(Nat, TokenInfo)] = [];
    private stable var usersEntries : [(Principal, UserInfo)] = [];
    private var tokens = HashMap.HashMap<Nat, TokenInfo>(1, Nat.equal, Hash.hash);
    private var users = HashMap.HashMap<Principal, UserInfo>(1, Principal.equal, Principal.hash);
    private stable var txs: [TxRecord] = [];
    private stable var txIndex: Nat = 0;

    // 新增 tx 记录
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
    
    // 给User新增token，更新信息
    private func _addTokenTo(to: Principal, tokenId: Nat) {
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

    // 从User中移除该token
    // 检查token存在 ； 检查是该token的owner
    // 从User的tokens中移除该token
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

    // 清除token的approval address 
    // 把该token从operator中的allowedTokens删除掉
    private func _clearApproval(owner: Principal, tokenId: Nat) {
        assert(_exists(tokenId) and _isOwner(owner, tokenId));
        switch (tokens.get(tokenId)) {
            case (?info) {
                if (info.operator != null) {
                    let op = _unwrap(info.operator);
                    let opInfo = _unwrap(users.get(op));
                    // 把该token从operator中的allowedTokens删除掉
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

    // 检查token存在
    // 
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

    // public update calls
    // 鉴权 -> 更新token信息 -> 更新User信息 -> tx记录
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

    // 一批次的mint，同上
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

    //销毁NFT
    // 检查token存在  -> 检查是此token的owner
    // burn: 清理授权 -> tansfer blackhole -> tx
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

    // 修改token的metadata
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

    // 将一个token 授权给 operator
    // 检查token存在 -> caller是owner/Approvedall(caller)
    // 不能授权给自己 
    // 更新token的operator -> 更新operator的allowedTokens
    // tx记录
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

    // 授权/清除授权(value)某人的全部资产给 operator
    // 不能授权给自己
    // 修改caller的operators -> 修改operator的allowedby -> tx 记录
    public shared(msg) func setApprovalForAll(operator: Principal, value: Bool): async TxReceipt {
        if(msg.caller == operator) {
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

    // 检查token存在 -> 检查是否是owner
    // 清除该token的approve address -> 把该token从operator中的allowedTokens删除掉
    // transfer -> tx记录
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
        _clearApproval(msg.caller, tokenId);
        _transfer(to, tokenId);
        let txid = addTxRecord(msg.caller, #transfer, ?tokenId, #user(msg.caller), #user(to), Time.now());
        return #ok(txid);
    };

// transfer 与 transferFrom 不同处在于操作者与应用场景的不同

    // 从from转token到to
    // 检查token存在 
    // 检查： 是owner / 该token授权给了caller / token的owner approvedall caller
    // 清除该token的approve address -> 把该token从operator中的allowedTokens删除掉
    // transfer -> tx记录
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
    
    // 批次transfer ，同上
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
};