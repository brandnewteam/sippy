// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "linphonesw",
    platforms: [
        .macOS(.v10_14)
    ],
    products: [
        .library(
            name: "linphonesw",
            targets: ["linphonesw"]
        )
    ],
    targets: [
        
			.binaryTarget(
				name: "ZXing",
				url: "https://download.linphone.org/releases/macosx/sdk/spm//linphone-sdk-swift-macos-5.5.16/XCFrameworks/ZXing.xcframework.zip",
				checksum: "cac8207dd626995c0c1b38a96f5c1ae11153d582167526d8d144074d7c0243a7"
			),
			
			.binaryTarget(
				name: "bctoolbox-tester",
				url: "https://download.linphone.org/releases/macosx/sdk/spm//linphone-sdk-swift-macos-5.5.16/XCFrameworks/bctoolbox-tester.xcframework.zip",
				checksum: "30c3346d8365e91929d283de461191fc8f87bbabb654ead70d22ae77825ab765"
			),
			
			.binaryTarget(
				name: "bctoolbox",
				url: "https://download.linphone.org/releases/macosx/sdk/spm//linphone-sdk-swift-macos-5.5.16/XCFrameworks/bctoolbox.xcframework.zip",
				checksum: "42b636c821afcf6a51bd07330b6142872475cf7eae4b503f32ca92f43a51ecb3"
			),
			
			.binaryTarget(
				name: "belcard",
				url: "https://download.linphone.org/releases/macosx/sdk/spm//linphone-sdk-swift-macos-5.5.16/XCFrameworks/belcard.xcframework.zip",
				checksum: "33d168c19ebcde42f8334329224950bbd0fa07488df11f1429f8b573b7b9b954"
			),
			
			.binaryTarget(
				name: "belle-sip",
				url: "https://download.linphone.org/releases/macosx/sdk/spm//linphone-sdk-swift-macos-5.5.16/XCFrameworks/belle-sip.xcframework.zip",
				checksum: "ca70a72ae143aaecc56ebc09a3f47a38167eb24773381d30471b462cc81f1503"
			),
			
			.binaryTarget(
				name: "belr",
				url: "https://download.linphone.org/releases/macosx/sdk/spm//linphone-sdk-swift-macos-5.5.16/XCFrameworks/belr.xcframework.zip",
				checksum: "fe6b8cc4866bc9117699c22ec6becc58c1d4f2aca157becc7238d0e3013d2e5b"
			),
			
			.binaryTarget(
				name: "lime",
				url: "https://download.linphone.org/releases/macosx/sdk/spm//linphone-sdk-swift-macos-5.5.16/XCFrameworks/lime.xcframework.zip",
				checksum: "c244128ff1d6b305932cf34f16af7ce2a18c8786f7e4541f66996de4585869f5"
			),
			
			.binaryTarget(
				name: "linphone",
				url: "https://download.linphone.org/releases/macosx/sdk/spm//linphone-sdk-swift-macos-5.5.16/XCFrameworks/linphone.xcframework.zip",
				checksum: "acf79c3ac1690185ffa682efa4a9a5d01e34141c7bffbb6e9b91cb0f015d2ba3"
			),
			
			.binaryTarget(
				name: "mediastreamer2",
				url: "https://download.linphone.org/releases/macosx/sdk/spm//linphone-sdk-swift-macos-5.5.16/XCFrameworks/mediastreamer2.xcframework.zip",
				checksum: "e149aa9a3814b300124b9a88bf00e4c31542ebb4e5765a45c435327b478e7c8c"
			),
			
			.binaryTarget(
				name: "msamr",
				url: "https://download.linphone.org/releases/macosx/sdk/spm//linphone-sdk-swift-macos-5.5.16/XCFrameworks/msamr.xcframework.zip",
				checksum: "7ac4026f0163f1ecd5fad9686d6b783bcde4e86b23edcf1f571cdd31284483b0"
			),
			
			.binaryTarget(
				name: "mscodec2",
				url: "https://download.linphone.org/releases/macosx/sdk/spm//linphone-sdk-swift-macos-5.5.16/XCFrameworks/mscodec2.xcframework.zip",
				checksum: "18f852ad1952783fddd25b320a1613908b6f42f43f138ab8e933fcd873721f94"
			),
			
			.binaryTarget(
				name: "msopenh264",
				url: "https://download.linphone.org/releases/macosx/sdk/spm//linphone-sdk-swift-macos-5.5.16/XCFrameworks/msopenh264.xcframework.zip",
				checksum: "9db7ca4f0b4bedfd025e4f75d0500f556503f047449d26873d45656065d62a79"
			),
			
			.binaryTarget(
				name: "ortp",
				url: "https://download.linphone.org/releases/macosx/sdk/spm//linphone-sdk-swift-macos-5.5.16/XCFrameworks/ortp.xcframework.zip",
				checksum: "fbc6acb77b0f3d88d1237780c0132a916dea5b1feeab0602201965b46d6fe411"
			),
			
		.target(
			name: "linphonexcframeworks",
			dependencies: ["ZXing", "bctoolbox-tester", "bctoolbox", "belcard", "belle-sip", "belr", "lime", "linphone", "mediastreamer2", "msamr", "mscodec2", "msopenh264", "ortp"]
		),

		.target(
			name: "linphonesw",
			dependencies: ["linphonexcframeworks"]
		)
    ]
)

