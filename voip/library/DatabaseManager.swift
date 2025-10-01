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
    let sipAddress: String?
    let phoneNumber: String?
    let remark: String?
}

struct ChatRoomLocal: Identifiable {
    let id: Int64
    let peerAddress: String
    let createTime: Int64
    let lastUpdate: Int64?
    let lastMessage: String?
}

struct ChatMessageLocal: Identifiable {
    let id: Int64
    let roomId: Int64
    let text: String
    let time: Int64
    let isOutgoing: Bool
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
    private let contactSipAddress = Expression<String?>("sipAddress")
    private let contactPhoneNumber = Expression<String?>("phoneNumber")
    private let contactRemark = Expression<String?>("remark")

    private let chatRooms = Table("chatRooms")
    private let chatRoomId = Expression<Int64>("id")
    private let chatRoomPeerAddress = Expression<String>("peerAddress")
    private let chatRoomCreateTime = Expression<Int64>("createTime")
    private let chatRoomLastUpdate = Expression<Int64?>("lastUpdate")
    private let chatRoomLastMessage = Expression<String?>("lastMessage")

    private let chatMessages = Table("chatMessages")
    private let messageId = Expression<Int64>("id")
    private let messageRoomId = Expression<Int64>("roomId")
    private let messageText = Expression<String>("text")
    private let messageTime = Expression<Int64>("time")
    private let messageIsOutgoing = Expression<Bool>("isOutgoing")

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
            t.column(contactSipAddress)
            t.column(contactPhoneNumber)
            t.column(contactRemark)
        })
        // 聊天室和消息表
        try? db.run(chatRooms.create(ifNotExists: true) { t in
            t.column(chatRoomId, primaryKey: .autoincrement)
            t.column(chatRoomPeerAddress)
            t.column(chatRoomCreateTime, defaultValue: Int64(Date().timeIntervalSince1970))
            t.column(chatRoomLastUpdate)
            t.column(chatRoomLastMessage)
        })
        try? db.run(chatMessages.create(ifNotExists: true) { t in
            t.column(messageId, primaryKey: .autoincrement)
            t.column(messageRoomId)
            t.column(messageText)
            t.column(messageTime)
            t.column(messageIsOutgoing)
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
            contactSipAddress <- contact.sipAddress,
            contactPhoneNumber <- contact.phoneNumber,
            contactRemark <- contact.remark
        )
        _ = try? db.run(insert)
    }

    func updateContact(_ contact: Contact) {
        let row = contacts.filter(contactId == contact.id)
        try? db.run(row.update(
            contactUsername <- contact.username,
            contactSipAddress <- contact.sipAddress,
            contactPhoneNumber <- contact.phoneNumber,
            contactRemark <- contact.remark
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
                sipAddress: row[contactSipAddress],
                phoneNumber: row[contactPhoneNumber],
                remark: row[contactRemark]
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
                    sipAddress: row[contactSipAddress],
                    phoneNumber: row[contactPhoneNumber],
                    remark: row[contactRemark]
                ))
            }
        } catch {
            print("查询联系人失败: \(error)")
        }
        return result
    }

    func addChatRoom(peerAddress: String){
        let insert = chatRooms.insert(chatRoomPeerAddress <- peerAddress, chatRoomCreateTime <- Int64(Date().timeIntervalSince1970))
        _ = try? db.run(insert)
    }

    func updateChatRoomLastMessage(roomId: Int64, message: String, time: Int64) {
        let row = chatRooms.filter(chatRoomId == roomId)
        try? db.run(row.update(
            chatRoomLastMessage <- message,
            chatRoomLastUpdate <- time
        ))
    }

    func findOrCreateChatRoom(peerAddress: String) -> ChatRoomLocal? {
        if let row = try? db.pluck(chatRooms.filter(chatRoomPeerAddress == peerAddress)) {
            return ChatRoomLocal(
                id: row[chatRoomId],
                peerAddress: row[chatRoomPeerAddress],
                createTime: row[chatRoomCreateTime],
                lastUpdate: row[chatRoomLastUpdate],
                lastMessage: row[chatRoomLastMessage]
            )
        } else {
            addChatRoom(peerAddress: peerAddress)
            if let newRow = try? db.pluck(chatRooms.filter(chatRoomPeerAddress == peerAddress)) {
                return ChatRoomLocal(
                    id: newRow[chatRoomId],
                    peerAddress: newRow[chatRoomPeerAddress],
                    createTime: newRow[chatRoomCreateTime],
                    lastUpdate: newRow[chatRoomLastUpdate],
                    lastMessage: newRow[chatRoomLastMessage]
                )
            }
        }
        return nil
    }

    func fetchChatRooms() -> [ChatRoomLocal] {
        var result: [ChatRoomLocal] = []
        do {
            for row in try db.prepare(chatRooms) {
                result.append(ChatRoomLocal(
                    id: row[chatRoomId],
                    peerAddress: row[chatRoomPeerAddress],
                    createTime: row[chatRoomCreateTime],
                    lastUpdate: row[chatRoomLastUpdate],
                    lastMessage: row[chatRoomLastMessage]
                ))
            }
        } catch {
            print("查询聊天房间失败: \(error)")
        }
        return result
    }

    func addChatMessage(roomId: Int64, text: String, time: Int64, isOutgoing: Bool) {
        let insert = chatMessages.insert(
            messageRoomId <- roomId,
            messageText <- text,
            messageTime <- time,
            messageIsOutgoing <- isOutgoing
        )
        _ = try? db.run(insert)
    }

    func fetchChatMessages(roomId: Int64) -> [ChatMessageLocal] {
        var result: [ChatMessageLocal] = []
        do {
            for row in try db.prepare(chatMessages.filter(messageRoomId == roomId)) {
                result.append(ChatMessageLocal(
                    id: row[messageId],
                    roomId: row[messageRoomId],
                    text: row[messageText],
                    time: row[messageTime],
                    isOutgoing: row[messageIsOutgoing]
                ))
            }
        } catch {
            print("查询聊天消息失败: \(error)")
        }
        return result
    }
}
