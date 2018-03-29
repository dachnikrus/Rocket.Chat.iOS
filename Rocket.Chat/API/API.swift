//
//  API.swift
//  Rocket.Chat
//
//  Created by Matheus Cardoso on 9/18/17.
//  Copyright © 2017 Rocket.Chat. All rights reserved.
//

import Foundation
import SwiftyJSON

protocol APIRequestMiddleware {
    var api: API { get }
    init(api: API)

    func handle<R: APIRequest>(_ request: inout R) -> APIError?
}

protocol APIFetcher {
    func fetch<R: APIRequest>(_ request: R, completion: ((_ result: APIResponse<R.APIResourceType>) -> Void)?)
    func fetch<R: APIRequest>(_ request: R, options: APIRequestOptions, sessionDelegate: URLSessionTaskDelegate?,
                              completion: ((_ result: APIResponse<R.APIResourceType>) -> Void)?)
}

extension APIFetcher {
    func fetch<R: APIRequest>(_ request: R, completion: ((APIResponse<R.APIResourceType>) -> Void)?) {
        fetch(request, options: .none, sessionDelegate: nil, completion: completion)
    }
}

typealias AnyAPIFetcher = Any & APIFetcher

class API: APIFetcher {
    let host: URL
    let version: Version

    var requestMiddlewares = [APIRequestMiddleware]()

    var authToken: String?
    var userId: String?

    convenience init?(host: String, version: Version = .zero) {
        guard let url = URL(string: host) else {
            return nil
        }

        self.init(host: url, version: version)
    }

    init(host: URL, version: Version = .zero) {
        self.host = host
        self.version = version

        requestMiddlewares.append(VersionMiddleware(api: self))
    }

    func fetch<R: APIRequest>(_ request: R, options: APIRequestOptions = .none, sessionDelegate: URLSessionTaskDelegate? = nil,
                              completion: ((_ result: APIResponse<R.APIResourceType>) -> Void)?) {
        var transformedRequest = request
        for middleware in requestMiddlewares {
            if let error = middleware.handle(&transformedRequest) {
                completion?(.error(error))
                return
            }
        }

        guard let request = transformedRequest.request(for: self, options: options) else {
            completion?(.error(.malformedRequest))
            return
        }

        var session: URLSession = URLSession.shared

        if let sessionDelegate = sessionDelegate {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 30

            session = URLSession(
                configuration: configuration,
                delegate: sessionDelegate,
                delegateQueue: nil
            )
        }

        let task = session.dataTask(with: request) { (data, _, error) in
            if let error = error {
                completion?(.error(.error(error)))
                return
            }

            guard let data = data else {
                completion?(.error(.noData))
                return
            }

            let json = try? JSON(data: data)
            completion?(APIResponse<R.APIResourceType>.resource(R.APIResourceType(raw: json)))
        }

        task.resume()
    }
}
