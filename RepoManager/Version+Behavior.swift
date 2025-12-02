//
//  File.swift
//  
//
//  Created by yungui chen on 2021/4/22.
//

import Foundation

extension Version {
    
    public func nextVersion(maxComponent: Int = 99, increasePrereleaseIdentifier: Bool = true) -> Version {
        var identifiers = self.prereleaseIdentifiers
        var hasIncreasedIdentifier = false
        if increasePrereleaseIdentifier {
            for i in (0 ..< identifiers.count).reversed() {
                let id = identifiers[i]
                if let x = Int(id) {
                    identifiers[i] = "\(x + 1)"
                    hasIncreasedIdentifier = true
                    break
                }
            }
        }
        if hasIncreasedIdentifier {
            return Version(major, minor, patch, prereleaseIdentifiers: identifiers)
        } else {
            if self.patch < maxComponent {
                return Version(major, minor, patch+1)
            } else if self.minor < maxComponent {
                return Version(major, minor+1, 0)
            } else { // try increase major
                return Version(major+1, 0, 0)
            }
        }
    }
}
