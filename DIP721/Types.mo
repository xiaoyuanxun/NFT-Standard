/**
 * Module     : types.mo
 * Copyright  : 2021 DFinance Team
 * License    : Apache 2.0 with LLVM Exception
 * Maintainer : DFinance Team <hello@dfinance.ai>
 * Stability  : Experimental
 */

import Time "mo:base/Time";
import TrieSet "mo:base/TrieSet";

module {

    // Collection 的 metadata
    public type Metadata = {
        logo: Text;
        name: Text;
        symbol: Text;
        desc: Text;
        totalSupply: Nat;
        owner: Principal;
        cycles: Nat;
    };
    
    // 一个NFT的定位
    public type Location = {
        #InCanister: Blob; // NFT encoded data
        #AssetCanister: (Principal, Blob); // asset canister id, storage key
        #IPFS: Text; // IPFS content hash
        #Web: Text; // URL pointing to the file
    };
    // NFT的属性
    // 例如key是眼镜，那么value就是红色的眼镜/GUCCI的眼镜
    public type Attribute = {
        key: Text;
        value: Text;
    };
    // NFT的metadata
    public type TokenMetadata = {
        filetype: Text; // jpg, png, mp4, etc.
        location: Location;
        attributes: [Attribute];
    };
    
    // 一个NFT的信息
    // operator -> 授权的操作员
    public type TokenInfo = {
        index: Nat;
        var owner: Principal;
        var metadata: ?TokenMetadata;
        var operator: ?Principal;
        timestamp: Time.Time;
    };
    public type TokenInfoExt = {
        index: Nat;
        owner: Principal;
        metadata: ?TokenMetadata;
        operator: ?Principal;
        timestamp: Time.Time;
    };

    public type UserInfo = {
        var operators: TrieSet.Set<Principal>;     // principals allowed to operate on the user's behalf
        var allowedBy: TrieSet.Set<Principal>;     // principals approved user to operate their's tokens
        var allowedTokens: TrieSet.Set<Nat>;       // tokens the user can operate
        var tokens: TrieSet.Set<Nat>;              // user's tokens
    };
    public type UserInfoExt = {
        operators: [Principal];
        allowedBy: [Principal];
        allowedTokens: [Nat];
        tokens: [Nat];
    };

    /// Update call operations
    public type Operation = {
        #mint: ?TokenMetadata;  
        #burn;
        #transfer;
        #transferFrom;
        #approve;
        #approveAll;
        #revokeAll; // revoke approvals
        #setMetadata;
    };

    /// Update call operation record fields
    public type Record = {
        #user: Principal;
        #metadata: ?TokenMetadata; // op == #setMetadata
    };
    // 交易记录
    public type TxRecord = {
        caller: Principal;
        op: Operation;
        index: Nat;
        tokenIndex: ?Nat;
        from: Record;
        to: Record;
        timestamp: Time.Time;
    };
};