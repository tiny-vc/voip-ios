//
//  DatabaseManager.swift
//  voip
//
//  Created by vc on 2025/9/20.
//

import Foundation
import SQLite

struct LocalAccount: Codable {
    let id: Int64
    let username: String
    let domain: String
    let password: String
    let transport: String
}

struct Contact: Identifiable, Hashable {
    let id: Int64
    let username: String
    let displayName: String
    let sipAddress: String
    let phoneNumber: String
    // 可选：添加更多字段
}

class DatabaseManager {
    static let shared = DatabaseManager()
    private let db: Connection

    // 表定义
    private let accounts = Table("accounts")
    private let contacts = Table("contacts")

    // 账号字段
    private let accountId = Expression<Int64>("id")
    private let accountUsername = Expression<String>("username")
    private let accountDomain = Expression<String>("domain")
    private let accountPassword = Expression<String>("password")
    private let accountTransport = Expression<String>("transport")

    // 联系人字段
    private let contactId = Expression<Int64>("id")
    private let contactUsername = Expression<String>("username")
    private let contactDisplayName = Expression<String>("displayName")
    private let contactSipAddress = Expression<String>("sipAddress")
    private let contactPhoneNumber = Expression<String>("phoneNumber")

    private init() {
        // 数据库文件路径
        let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        db = try! Connection("\(path)/voip.sqlite3")
        createTables()
    }

    private func createTables() {
        // 账号表
        try? db.run(accounts.create(ifNotExists: true) { t in
            t.column(accountId, primaryKey: .autoincrement)
            t.column(accountUsername)
            t.column(accountDomain)
            t.column(accountPassword)
            t.column(accountTransport)
        })
        // 联系人表
        try? db.run(contacts.create(ifNotExists: true) { t in
            t.column(contactId, primaryKey: .autoincrement)
            t.column(contactUsername)
            t.column(contactDisplayName)
            t.column(contactSipAddress)
            t.column(contactPhoneNumber)
        })
    }

    // MARK: - 账号操作

    func saveAccount(username: String, domain: String, password: String, transport: String) {
        // 只保存一个账号，先清空再插入
        try? db.run(accounts.delete())
        let insert = accounts.insert(
            accountUsername <- username,
            accountDomain <- domain,
            accountPassword <- password,
            accountTransport <- transport
        )
        _ = try? db.run(insert)
    }

    func loadAccount() -> LocalAccount? {
        if let row = try? db.pluck(accounts) {
            return LocalAccount(
                id: row[accountId],
                username: row[accountUsername],
                domain: row[accountDomain],
                password: row[accountPassword],
                transport: row[accountTransport]
            )
        }
        return nil
    }

    func clearAccount() {
        try? db.run(accounts.delete())
    }

    // MARK: - 联系人操作

    func addContact(_ contact: Contact) {
        let insert = contacts.insert(
            contactUsername <- contact.username,
            contactDisplayName <- contact.displayName,
            contactSipAddress <- contact.sipAddress,
            contactPhoneNumber <- contact.phoneNumber
        )
        _ = try? db.run(insert)
    }

    func updateContact(_ contact: Contact) {
        let row = contacts.filter(contactId == contact.id)
        try? db.run(row.update(
            contactUsername <- contact.username,
            contactDisplayName <- contact.displayName,
            contactSipAddress <- contact.sipAddress,
            contactPhoneNumber <- contact.phoneNumber
        ))
    }

    func deleteContact(id: Int64) {
        let row = contacts.filter(contactId == id)
        try? db.run(row.delete())
    }

    func findContact(byId id: Int64) -> Contact? {
        if let row = try? db.pluck(contacts.filter(contactId == id)) {
            return Contact(
                id: row[contactId],
                username: row[contactUsername],
                displayName: row[contactDisplayName],
                sipAddress: row[contactSipAddress],
                phoneNumber: row[contactPhoneNumber]
            )
        }
        return nil
    }

    func fetchContacts() -> [Contact] {
        var result: [Contact] = []
        do {
            for row in try db.prepare(contacts) {
                result.append(Contact(
                    id: row[contactId],
                    username: row[contactUsername],
                    displayName: row[contactDisplayName],
                    sipAddress: row[contactSipAddress],
                    phoneNumber: row[contactPhoneNumber]
                ))
            }
        } catch {
            print("查询联系人失败: \(error)")
        }
        return result
    }
}
