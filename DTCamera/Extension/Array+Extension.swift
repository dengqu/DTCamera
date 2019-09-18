//
//  Array+Extension.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/9/16.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import Foundation

extension Array {
    func size() -> Int {
        return MemoryLayout<Element>.stride * self.count
    }
}
