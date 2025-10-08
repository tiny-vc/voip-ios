//
//  Http.swift
//  voip
//
//  Created by vc on 2025/9/27.
//


import Foundation

enum HttpContentType: String {
    case json = "application/json"
    case form = "application/x-www-form-urlencoded"
    //case multipart = "multipart/form-data"
}

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
    func post(url: String, body: [String: Any?], headers: [String: String]? = nil, contentType: HttpContentType = .json, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let urlObj = URL(string: url) else {
            completion(.failure(NSError(domain: "InvalidURL", code: -1)))
            return
        }
        var request = URLRequest(url: urlObj)
        request.httpMethod = "POST"
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.setValue(contentType.rawValue, forHTTPHeaderField: "Content-Type")
        let newBody = body.filter { $0.value != nil } as [String: Any]
        if contentType == .form {
            let formBody = newBody.map { "\($0)=\("\($1)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
            request.httpBody = formBody.data(using: .utf8)
        } else {
            request.httpBody = try? JSONSerialization.data(withJSONObject: newBody)
        }       
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