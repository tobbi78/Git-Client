//
//  Git_ClientApp.swift
//  Git-Client
//
//  Created by Tobias Florian on 10.09.26.
//

import SwiftUI

@main
struct Git_ClientApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if let repository = appModel.openedRepository {
                    MainWindowView(repository: repository)
                } else {
                    RepositoryBrowserView()
                }
            }
            .environment(appModel)
        }
        .defaultSize(width: 1200, height: 780)
    }
}
