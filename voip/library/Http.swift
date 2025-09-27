//
//  Http.swift
//  voip
//
//  Created by vc on 2025/9/27.
//

import Foundation


import Foundation

class HttpClient {
    static let shared = HttpClient()
    private let session = URLSession.shared

    // GET 请求
    func get(url: String, headers: [String: String]? = nil, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let urlObj = URL(string: url) else {
            completion(.failure(NSError(domain: "InvalidURL", code: -1)))
            return
        }
        var request = URLRequest(url: urlObj)
        request.httpMethod = "GET"
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
            } else if let data = data {
                completion(.success(data))
            } else {
                completion(.failure(NSError(domain: "NoData", code: -2)))
            }
        }.resume()
    }

    // POST 请求
    func post(url: String, body: [String: Any], headers: [String: String]? = nil, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let urlObj = URL(string: url) else {
            completion(.failure(NSError(domain: "InvalidURL", code: -1)))
            return
        }
        var request = URLRequest(url: urlObj)
        request.httpMethod = "POST"
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
            } else if let data = data {
                completion(.success(data))
            } else {
                completion(.failure(NSError(domain: "NoData", code: -2)))
            }
        }.resume()
    }

    // 通用请求（支持自定义方法和body）
    func request(url: String, method: String, body: Data? = nil, headers: [String: String]? = nil, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let urlObj = URL(string: url) else {
            completion(.failure(NSError(domain: "InvalidURL", code: -1)))
            return
        }
        var request = URLRequest(url: urlObj)
        request.httpMethod = method
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = body
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
            } else if let data = data {
                completion(.success(data))
            } else {
                completion(.failure(NSError(domain: "NoData", code: -2)))
            }
        }.resume()
    }
}