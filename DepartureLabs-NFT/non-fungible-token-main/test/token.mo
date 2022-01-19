import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Iter "mo:base/Iter";
import Principal "mo:base/Principal";

import T "../src/token";

var nfts = T.NFTs(0, 0, []);
assert(nfts.currentID() == 0);
assert(nfts.payloadSize() == 0);
assert(Iter.size(nfts.entries()) == 0);
assert(nfts.getTotalMinted() == 0);

// Check minted egg without owner.
let hub = Principal.fromText("2ibo7-dia");
let contentType = "application/octet-stream";
let (id0, owner0) : (Text, Principal) = switch (await nfts.mint(hub, {
    payload     = #Payload(Blob.fromArray([0x00]));
    contentType = contentType;
    owner       = null;
    properties  = [];
    isPrivate   = false;
})) {
    case (#err(_)) { assert(false); ("0", hub); };
    case (#ok(id0, owner0)) {
        assert(id0 == "0");
        assert(owner0 == hub);
        switch (nfts.ownerOf(id0)) {
            case (#err(_)) {
                assert(false);
            };
            case (#ok(v)) {
                assert(v == hub);
            };
        };
        assert(nfts.tokensOf(hub) == ["0"]);
        let t0 = nfts.getToken(id0);
        switch (nfts.getToken(id0)) {
            case (#err(_)) {
                assert(false);
            };
            case (#ok(v)) {
                assert(v.payload == [Blob.fromArray([0x00])]);
                assert(v.contentType == contentType);
            };
        };
        (id0, owner0);
    };
};

// Check minted egg with owner from staged data.
let p0 = Principal.fromText("uuc56-gyb");
// Stage asset.Blob
let id : Text = switch (await nfts.writeStaged(#Init{
    size     = 2;
    callback = null;
})) {
    case (#err(e)) {
        Debug.print(e);
        assert(false);
        "0";
    };
    case (#ok(id)) { id; }; 
};
ignore await nfts.writeStaged(#Chunk{
    id        = id;
    chunk     = Blob.fromArray([0x00]);
    callback = null;
});
ignore await nfts.writeStaged(#Chunk{
    id        = id;
    chunk     = Blob.fromArray([0x01]);
    callback = null;
});

switch (await nfts.mint(hub, {
    payload     = #StagedData(id);
    contentType = contentType;
    owner       = ?p0;
    properties  = [];
    isPrivate   = false;
})) {
    case (#err(e)) {
        Debug.print(e);
        assert(false);
    };
    case (#ok(id1, owner1)) {
        assert(id1 == "1");
        assert(owner1 == p0);
        switch (nfts.ownerOf(id1)) {
            case (#err(_)) { assert(false); };
            case (#ok(v)) {
                assert(v == p0);
            };
        };
        assert(nfts.tokensOf(p0) == ["1"]);
        switch (nfts.getToken(id1)) {
            case (#err(_)) { assert(false); };
            case (#ok(v)) {
                assert(v.payload == [
                    Blob.fromArray([0x00]),
                    Blob.fromArray([0x01])
                ]);
                assert(v.contentType == contentType);
            };
        };
    };
};

// Check authorization.
assert(not nfts.isAuthorized(p0, id0));
assert(nfts.authorize({
    id           = id0;
    p            = p0;
    isAuthorized = true;
}));
assert(nfts.isAuthorized(p0, id0));
assert(nfts.authorize({
    id           = id0;
    p            = p0;
    isAuthorized = false;
}));
assert(not nfts.isAuthorized(p0, id0));
assert(nfts.authorize({
    id           = id0;
    p            = p0;
    isAuthorized = true;
}));

// Transfer token.
ignore await nfts.transfer(p0, id0);
assert(nfts.tokensOf(p0) == ["1", "0"]);
assert(nfts.tokensOf(hub) == []);
assert(nfts.ownerOf("0") == #ok(p0));
assert(nfts.ownerOf("1") == #ok(p0));
