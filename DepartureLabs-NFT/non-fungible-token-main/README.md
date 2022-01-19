# Introduction

> WIP

Our goal for this project is to develop a non-fungible token standard which leverages the unique properties of the IC and enables builders to create entire experiences from a single contract. Our approach is guided by the following exploratory questions: What can be an NFT? What can it be used for? Who can access it? How and where is it accessed? What properties does it have - can they change? Who can change them?

Ultimately, this is a big step away from the current standards, and this is most definitely tossing in everything but the kitchen sink.. Still, we hope you'll find what we've come up with to be a compelling first step!

# Development Status - **Early Alpha**

Notes:

* 8/7/2021. Hazel - The code hasn't been cleaned up. Instead of keeping this on my laptop I thought it was time to just push it out and start getting feedback.

# Features

* 🟢 - Ready
* 🟠 - In Progress (~50% Complete)
* ⚪ - Not Started

## Web Native - 🟢

The following standard supports serving NFTs directly over HTTP, and we've added the ability to define a `content-type`. This means your NFTs can be JSON, JavaScript, HTML, Images, Video, Audio, anything really! Want some inspiration? Check out [MIME Types](https://developer.mozilla.org/en-US/docs/Web/HTTP/Basics_of_HTTP/MIME_types). 

Yes, this means you can embed your jpegs directly in HTML. Maybe you mint an image, and then embed that image in an HTML page you mint. 

> I don't know why you'd do that, but it sounds really cool!


We also support streaming large assets in and out of the contract 😄.

Check out a demo HTML NFT [here](https://4gpah-faaaa-aaaaf-qabfq-cai.raw.ic0.app/nft/7) 👀.

## Static Assets - 🟢

We've built in support for mutable static assets. This gives the contract the ability to serve experiences natively. Build a VR frontend that loads NFT assets all in one contract. Build a gallery for your NFT art. Its up to you!

## Properties - 🟠

Leveraging candid we built out a typed property interface with basic support for nested classes. This allows you define complex hierarchical property structures. Properties are queryable. Properties can be either mutable or immutable. Mutable properties could be leveraged for NFTs that evolve and level up, or items in games. We'll be releasing clients to wrap things up nicely in JS, Rust, and Motoko.

## Private NFTs - 🟠

We support the ability to mint NFTs which can only be accessed by the owner.

## Events - 🟠

Do things in response to activities against the contract. 

## Per-token Access Control - ⚪

We're working on building a per-token ACL layer. This combined with Private NFTs will enable things like paywalled content.

## Editions - ⚪

Issue multiple editions.

