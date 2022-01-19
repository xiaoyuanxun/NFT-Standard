import HashMap "mo:base/HashMap";
import Principal "mo:base/Principal";

import H "../src/mapHelper";

// Check search functions.
assert(H.textEqual("foo")("foo"));
assert(not H.textEqual("foo")("bar"));

assert(H.textNotEqual("foo")("bar"));
assert(not H.textNotEqual("foo")("foo"));

let p0 = Principal.fromText("2ibo7-dia"); // Random example principal ids.
let p1 = Principal.fromText("uuc56-gyb");

assert(H.principalEqual(p0)(p0));
assert(not H.principalEqual(p0)(p1));

let map = HashMap.HashMap<Principal, [Text]>(10, Principal.equal, Principal.hash);
H.add<Principal, Text>(map, p0, "foo", H.textEqual("foo"));
switch (map.get(p0)) {
    case null { assert(false) };
    case (? vs) {
        assert(vs == ["foo"]);
    };
};
H.add<Principal, Text>(map, p0, "bar", H.textEqual("bar"));
assert(not H.addIfNotLimit<Principal, Text>(map, p0, "baz", 2, H.textEqual("baz")));
switch (map.get(p0)) {
    case null { assert(false) };
    case (? vs) {
        assert(vs == ["foo", "bar"]);
    };
};

// Transfer ownership example:
H.add<Principal, Text>(map, p1, "bar", H.textEqual("bar"));
H.filter<Principal, Text>(map, p0, "bar", H.textNotEqual("bar"));

switch (map.get(p0)) {
    case null { assert(false) };
    case (? vs) {
        assert(vs == ["foo"]);
    };
};
switch (map.get(p1)) {
    case null { assert(false) };
    case (? vs) {
        assert(vs == ["bar"]);
    };
};
