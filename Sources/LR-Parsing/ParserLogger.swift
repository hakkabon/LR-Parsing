//
//  GrammarLogger.swift
//  LR-parsing
//
//  Created by Ulf Akerstedt-Inoue on 2025/09/21.
//  Copyright © 2025 hakkabon software. All rights reserved.
//

import OSLog

extension Logger {
    /// Using your bundle identifier is a great way to ensure a unique identifier.
    private static var subsystem = "com.grammar.hakkabon"

    /// Logs all processing related to the parsing domain.
    static let lr = Logger(subsystem: subsystem, category: "LR")

}
