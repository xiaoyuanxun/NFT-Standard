import P "../src/property";

import D "mo:base/Debug";

let ps : P.Properties = [{
    name      = "prop0";
    value     = #Nat(99);
    immutable = true;
}];

// Can not update immutable property.
assert(P.update(ps, [
    {
        name  = "prop0";
        mode  = #Set(#Nat(0));
    },
]) == #err(#Immutable));

// Add one property.
assert(P.update(ps, [
    {
        name  = "prop1";
        mode  = #Set(#Nat(0));
    },
]) == #ok([
    {
        name      = "prop0";
        value     = #Nat(99);
        immutable = true;
    },
    {
        name      = "prop1";
        value     = #Nat(0);
        immutable = false;
    },
]));

// Only get one property.
assert(P.get(ps, [
    {
        name = "prop0";
        next = [];
    }
]) == #ok([{
    name      = "prop0";
    value     = #Nat(99);
    immutable = true;
}]));

// Property does not exist.
assert(P.get(ps, [
    {
        name = "prop99";
        next = [];
    }
]) == #err(#NotFound));

// Create class property.
let psc : P.Properties = switch (P.update([], [
    {
        name  = "prop0";
        mode  = #Next([
            {
                name  = "prop1";
                mode  = #Set(#Nat(0));
            },
            {
                name  = "prop2";
                mode  = #Set(#Nat(99));
            },
        ]);
    },
])) {
    case (#err(_)) { assert(false); []; };
    case (#ok(ps)) { ps;                };
};
assert(psc == [
    {
        name      = "prop0";
        value     = #Class([
            {
                name      = "prop2";
                value     = #Nat(99);
                immutable = false;
            },
            {
                name      = "prop1";
                value     = #Nat(0);
                immutable = false;
            },
        ]);
        immutable = false;
    },
]);

// Get one of the sub-properties.
assert(P.get(psc, [{
    name = "prop0";
    next = [{
        name = "prop1";
        next = [];
    }];
}]) == #ok([
    {
        name      = "prop0";
        value     = #Class([
            {
                name      = "prop1";
                value     = #Nat(0);
                immutable = false;
            },
        ]);
        immutable = false;
    },
]));
