//
//  main.swift
//  swifttls
//
//  Created by Nico Schmidt on 16.05.15.
//  Copyright (c) 2015 Nico Schmidt. All rights reserved.
//

import Foundation
//import SwiftTLS
import OpenSSL
import SwiftHelper

func server()
{
    var port = 12345
    var certificatePath : String?
    var dhParametersPath : String?
    if Process.arguments.count >= 3 {
        let portString = Process.arguments[2]
        if let portNumber = Int(portString) {
            port = portNumber
        }
    }

    if Process.arguments.count >= 4{
        certificatePath = (Process.arguments[3] as NSString).expandingTildeInPath
    }

    if Process.arguments.count >= 5 {
        dhParametersPath = Process.arguments[4]
    }
    
    print("Listening on port \(port)")
    
    var configuration = TLSConfiguration(protocolVersion: .v1_2)
    
    let cipherSuites : [CipherSuite] = [
        .TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
        .TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,
        .TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA,
//        .TLS_DHE_RSA_WITH_AES_256_CBC_SHA,
//        .TLS_RSA_WITH_AES_256_CBC_SHA
        ]
    
    configuration.cipherSuites = cipherSuites
//    configuration.identity = Identity(name: "Internet Widgits Pty Ltd")!
    configuration.identity = PEMFileIdentity(pemFile: certificatePath!)
    if let dhParametersPath = dhParametersPath {
        configuration.dhParameters = DiffieHellmanParameters.fromPEMFile(dhParametersPath)
    }
    configuration.ecdhParameters = ECDiffieHellmanParameters(namedCurve: .secp256r1)
    
    let server = TLSSocket(configuration: configuration, isClient: false)
    let address = IPv4Address.localAddress()
    address.port = UInt16(port)
    
    while true {
        do {
            let clientSocket = try server.acceptConnection(address)
            
//            while true {
            let data = try clientSocket.read(count: 1024)
            let string = String.fromUTF8Bytes(data)!
            let contentLength = string.utf8.count
            let response = "200 OK\nConnection: Close\nContent-Length: \(contentLength)\n\n\(string)"
            try clientSocket.write(response)
            clientSocket.close()
//            }
        }
        catch(let error) {
            if let tlserror = error as? TLSError {
                switch tlserror {
                case .error(let message):
                    print("Error: \(message)")
                case .alert(let alert, let level):
                    print("Alert: \(level) \(alert)")
                }
                
                continue
            }
            
            
            print("Error: \(error)")
        }
    }
}

func connectTo(host : String, port : Int = 443, protocolVersion: TLSProtocolVersion = .v1_2, cipherSuite : CipherSuite? = nil)
{
    var configuration = TLSConfiguration(protocolVersion: protocolVersion)
    
    if let cipherSuite = cipherSuite {
        configuration.cipherSuites = [cipherSuite]
    }
    else if protocolVersion == .v1_2 {
        configuration.cipherSuites = [
//            .TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
            .TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
//            .TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,
//            .TLS_DHE_RSA_WITH_AES_256_CBC_SHA,
//            .TLS_RSA_WITH_AES_256_CBC_SHA
        ]
    }
    else {
        configuration.cipherSuites = [
            .TLS_DHE_RSA_WITH_AES_256_CBC_SHA,
            .TLS_RSA_WITH_AES_256_CBC_SHA
        ]
    }
    
    let socket = TLSSocket(configuration: configuration)
    socket.context.hostNames = [host]
    
    do {
        let address = IPAddress.addressWithString(host, port: port)!
        print("Connecting to \(address.hostname) (\(address.string!))")
        try socket.connect(address)
        
        print("Connection established using cipher suite \(socket.context.cipherSuite!)")
        
        try socket.write([UInt8]("GET / HTTP/1.1\r\nHost: \(host)\r\n\r\n".utf8))
        let data = try socket.read(count: 4096)
        print("\(data.count) bytes read.")
        print("\(String.fromUTF8Bytes(data)!)")
        socket.close()
    } catch (let error) {
        print("Error: \(error)")
    }
    
    return
}

func parseASN1()
{
    let data = try! Data(contentsOf: URL(fileURLWithPath: "embedded.mobileprovision"))
    
    let object = ASN1Parser(data: data).parseObject()
    
    ASN1_printObject(object!)
}

func probeCipherSuitesForHost(host : String, port : Int, protocolVersion: TLSProtocolVersion = .v1_2)
{
    class StateMachine : TLSContextStateMachine
    {
        weak var socket : TLSSocket!
        var cipherSuite : CipherSuite!
        init(socket : TLSSocket)
        {
            self.socket = socket
        }
        
        func shouldContinueHandshakeWithMessage(message: TLSHandshakeMessage) -> Bool
        {
            if let hello = message as? TLSServerHello {
                print("\(hello.cipherSuite)")

                return false
            }
            
            return true
        }
        
        func didReceiveAlert(alert: TLSAlertMessage) {
//            print("\(cipherSuite) not supported")
//            print("NO")
        }
    }

    guard let address = IPAddress.addressWithString(host, port: port) else { print("Error: No such host \(host)"); return }

    for cipherSuite in CipherSuite.allValues {
        let socket = TLSSocket(protocolVersion: protocolVersion)
        let stateMachine = StateMachine(socket: socket)
        socket.context.stateMachine = stateMachine

        socket.context.configuration.cipherSuites = [cipherSuite]
        
        do {
            stateMachine.cipherSuite = cipherSuite
            try socket.connect(address)
        } catch let error as SocketError {
            switch error {
            case .closed:
                socket.close()
            
            default:
                print("Error: \(error)")
            }
        }
        catch {
//            print("Unhandled error: \(error)")
        }
    }
}

guard Process.arguments.count >= 2 else {
    print("Error: No command given")
    exit(1)
}

let command = Process.arguments[1]

enum Error : ErrorProtocol
{
    case Error(String)
}

switch command
{
case "client":
    guard Process.arguments.count > 2 else {
        print("Error: Missing arguments for subcommand \"\(command)\"")
        exit(1)
    }
    
    var host : String? = nil
    var port : Int = 443
    var protocolVersion = TLSProtocolVersion.v1_2
    var cipherSuite : CipherSuite? = nil

    do {
        var argumentIndex : Int = 2
        while true
        {
            if Process.arguments.count <= argumentIndex {
                break
            }
            
            var argument = Process.arguments[argumentIndex]
            
            argumentIndex += 1
            
            switch argument
            {
            case "--connect":
                if Process.arguments.count <= argumentIndex {
                    throw Error.Error("Missing argument for --connect")
                }
                
                var argument = Process.arguments[argumentIndex]
                argumentIndex += 1
                
                if argument.contains(":") {
                    let components = argument.components(separatedBy: ":")
                    host = components[0]
                    guard let p = Int(components[1]), p > 0 && p < 65536 else {
                        throw Error.Error("\(components[1]) is not a valid port number")
                    }
                    
                    port = p
                }
                else {
                    host = argument
                }
                
            case "--TLSVersion":
                if Process.arguments.count <= argumentIndex {
                    throw Error.Error("Missing argument for --TLSVersion")
                }
                
                var argument = Process.arguments[argumentIndex]
                argumentIndex += 1

                switch argument
                {
                case "1.0":
                    protocolVersion = .v1_0

                case "1.1":
                    protocolVersion = .v1_1

                case "1.2":
                    protocolVersion = .v1_2

                default:
                    throw Error.Error("\(argument) is not a valid TLS version")
                }
                
            case "--cipherSuite":
                if Process.arguments.count <= argumentIndex {
                    throw Error.Error("Missing argument for --cipherSuite")
                }
                
                var argument = Process.arguments[argumentIndex]
                argumentIndex += 1

                cipherSuite = CipherSuite(fromString:argument)
                
            default:
                print("Error: Unknown argument \(argument)")
                exit(1)
            }
        }
    }
    catch Error.Error(let message) {
        print("Error: \(message)")
        exit(1)
    }

    guard let hostName = host else {
        print("Error: Missing argument --connect host[:port]")
        exit(1)
    }

    connectTo(host: hostName, port: port, protocolVersion: protocolVersion, cipherSuite: cipherSuite)
    
case "server":
    server()
    
case "probeCiphers":
    guard Process.arguments.count > 2 else {
        print("Error: Missing arguments for subcommand \"\(command)\"")
        exit(1)
    }
    
    var host : String? = nil
    var port : Int = 443
    var protocolVersion = TLSProtocolVersion.v1_2
    
    do {
        var argumentIndex : Int = 2
        while true
        {
            if Process.arguments.count <= argumentIndex {
                break
            }
            
            var argument = Process.arguments[argumentIndex]
            
            argumentIndex += 1
            
            switch argument
            {
            case "--TLSVersion":
                if Process.arguments.count <= argumentIndex {
                    throw Error.Error("Missing argument for --TLSVersion")
                }
                
                var argument = Process.arguments[argumentIndex]
                argumentIndex += 1
                
                switch argument
                {
                case "1.0":
                    protocolVersion = .v1_0
                    
                case "1.1":
                    protocolVersion = .v1_1
                    
                case "1.2":
                    protocolVersion = .v1_2
                    
                default:
                    throw Error.Error("\(argument) is not a valid TLS version")
                }
                
            default:
                if argument.contains(":") {
                    let components = argument.components(separatedBy: ":")
                    host = components[0]
                    guard let p = Int(components[1]), p > 0 && p < 65536 else {
                        throw Error.Error("\(components[1]) is not a valid port number")
                    }
                    
                    port = p
                }
                else {
                    host = argument
                }
            }
        }
    }
    catch Error.Error(let message) {
        print("Error: \(message)")
        exit(1)
    }
    
    guard let hostName = host else {
        print("Error: Missing argument --connect host[:port]")
        exit(1)
    }
    
    probeCipherSuitesForHost(host: hostName, port: port, protocolVersion: protocolVersion)
    
case "pem":
    guard Process.arguments.count > 2 else {
        print("Error: Missing arguments for subcommand \"\(command)\"")
        exit(1)
    }

    let file = Process.arguments[2]

    let sections = ASN1Parser.sectionsFromPEMFile(file)
    for (name, section) in sections {
        print("\(name):")
        ASN1_printObject(section)
    }

case "asn1parse":

    guard Process.arguments.count > 2 else {
        print("Error: Missing arguments for subcommand \"\(command)\"")
        exit(1)
    }

    let file = Process.arguments[2]
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)) else {
        print("Error: No such file \"\(file)\"")
        exit(1)
    }
    
    if let object = ASN1Parser(data: data).parseObject()
    {
        ASN1_printObject(object)
    }
    else {
        print("Error: Could not parse \"\(file)\"")
    }
    
    break

case "p12":
    
    guard Process.arguments.count > 2 else {
        print("Error: Missing arguments for subcommand \"\(command)\"")
        exit(1)
    }
    
    let file = Process.arguments[2]
    let data = try? Data(contentsOf: URL(fileURLWithPath: file))
    if  let data = data,
        let object = ASN1Parser(data: data).parseObject()
    {
        if let sequence = object as? ASN1Sequence,
            let subSequence = sequence.objects[1] as? ASN1Sequence,
            let oid = subSequence.objects.first as? ASN1ObjectIdentifier, OID(id: oid.identifier) == .pkcs7_data,
            let taggedObject = subSequence.objects[1] as? ASN1TaggedObject,
            let octetString = taggedObject.object as? ASN1OctetString
        {
            if let o = ASN1Parser(data: octetString.value).parseObject() {
                ASN1_printObject(o)
            }
        }
    }
    else {
        print("Error: Could not parse \"\(file)\"")
    }
    
    break
    
default:
    print("Error: Unknown command \"\(command)\"")
}
