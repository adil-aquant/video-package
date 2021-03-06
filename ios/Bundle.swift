//
//  Bundle.swift
//  AquantVideoModule
//
//  Created by Adil on 13/01/22.
//

import class Foundation.Bundle

private class BundleFinder{}

extension Foundation.Bundle {
    static var _module : Bundle {
        let bundleName = "AquantVideoModule"
        
        let candidates = [
            // Bundle should be present here when the package is linked into an App.
            Bundle.main.resourceURL,

            // Bundle should be present here when the package is linked into a framework.
            Bundle(for: BundleFinder.self).resourceURL,

            // For command-line tools.
            Bundle.main.bundleURL,
        ]

        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                return bundle
            }
        }
        // This should be a fallback for Carthage.
        return Bundle(for: CallViewController.self)
    }
}
