import Result "mo:base/Result";
module {
    public type Callback = shared () -> async ();
    public func notify(callback : ?Callback) : async () {
        switch(callback) {
            case null   return;
            case (? cb) {ignore cb()};
        };
    };

    public type Error = {
        #Unauthorized;
        #NotFound;
        #InvalidRequest;
        #AuthorizedPrincipalLimitReached : Nat;
        #Immutable;
        #FailedToWrite : Text;
    };
}