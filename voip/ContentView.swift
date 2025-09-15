//
//  ContentView.swift
//  voip
//
//  Created by vc on 2025/9/8.
//

import SwiftUI
import linphonesw

struct ContentView: View {
    @StateObject var vm = LinPhoneViewModel()
    @State private var domain = "180.97.215.207:5555"
    @State private var username = "jack"
    @State private var password = "1"
    @State private var transport = "udp"

    var body: some View {
        Group {
            if !vm.isRegistered {
                // 登录界面
                VStack(spacing: 16) {
                    Text("SIP 登录").font(.largeTitle)
                    TextField("服务器", text: $domain)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    TextField("用户名", text: $username)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    SecureField("密码", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Picker("传输协议", selection: $transport) {
                        Text("UDP").tag("udp")
                        Text("TCP").tag("tcp")
                        Text("TLS").tag("tls")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    Button("登录") {
                        let options = LinPhone.Options(
                            domain: domain,
                            username: username,
                            password: password,
                            transport: transport,
                            logLevel: .Error
                        )
                        vm.setup(options: options)
                        vm.login()
                    }
                    .padding()
                    if let error = vm.errorMessage {
                        Text(error).foregroundColor(.red)
                    }
                    Spacer()
                }
                .padding()
            } else {
                // 主界面
                MainTabView(vm: vm)
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}

struct MainTabView: View {
    @ObservedObject var vm: LinPhoneViewModel

    var body: some View {
        TabView {
            ContactsView()
                .tabItem {
                    Label("联系人", systemImage: "person.2")
                }
            CallsView(vm: vm)
                .tabItem {
                    Label("通话", systemImage: "phone")
                }
            ChatView(vm: vm)
                .tabItem {
                    Label("聊天", systemImage: "bubble.left.and.bubble.right")
                }
            SettingsView(vm: vm)
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
        }
    }
}

// 以下为各Tab的简单占位实现，你可根据业务需求完善

struct ContactsView: View {
    var body: some View {
        VStack {
            Text("联系人")
            Spacer()
        }
    }
}

struct CallsView: View {
    @ObservedObject var vm: LinPhoneViewModel
    @State private var dialNumber: String = "sip:vc@180.97.215.207"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("通话记录").font(.headline)
            List(vm.calls, id: \.id) { call in
                VStack(alignment: .leading) {
                    Text("对方: \(call.remoteAddress?.asString() ?? "unknown")")
                    Text("时长: \(call.duration)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            Divider()
            Text("拨号").font(.headline)
            HStack {
                TextField("请输入号码", text: $dialNumber)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("呼叫") {
                    vm.call(to: dialNumber)
                }
                .disabled(dialNumber.isEmpty)
            }
            Spacer()
        }
        .padding()
    }
}

struct ChatView: View {
    @ObservedObject var vm: LinPhoneViewModel
    var body: some View {
        VStack {
            Text("聊天")
            Spacer()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var vm: LinPhoneViewModel
    var body: some View {
        VStack {
            Text("设置")
            Button("注销") {
                vm.logout()
            }
            Spacer()
        }
    }
}



