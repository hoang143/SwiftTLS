//
//  SHA512.swift
//  SwiftTLS
//
//  Created by Nico Schmidt on 16.04.18.
//  Copyright © 2018 Nico Schmidt. All rights reserved.
//

private func Ch(_ x: UInt64, _ y: UInt64, _ z: UInt64) -> UInt64 {
    return (x & y) ^ (~x & z)
}

private func Maj(_ x: UInt64, _ y: UInt64, _ z: UInt64) -> UInt64 {
    return (x & y) ^ (x & z) ^ (y & z)
}

private func Sigma0(_ x: UInt64) -> UInt64 {
    return x.rotr(28) ^ x.rotr(34) ^ x.rotr(39)
}

private func Sigma1(_ x: UInt64) -> UInt64 {
    return x.rotr(14) ^ x.rotr(18) ^ x.rotr(41)
}

private func sigma0(_ x: UInt64) -> UInt64 {
    return x.rotr(1) ^ x.rotr(8) ^ x.shr(7)
}

private func sigma1(_ x: UInt64) -> UInt64 {
    return x.rotr(19) ^ x.rotr(61) ^ x.shr(6)
}

private let K: [UInt64] = [
    0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc,
    0x3956c25bf348b538, 0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118,
    0xd807aa98a3030242, 0x12835b0145706fbe, 0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2,
    0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235, 0xc19bf174cf692694,
    0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
    0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5,
    0x983e5152ee66dfab, 0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4,
    0xc6e00bf33da88fc2, 0xd5a79147930aa725, 0x06ca6351e003826f, 0x142929670a0e6e70,
    0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed, 0x53380d139d95b3df,
    0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
    0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30,
    0xd192e819d6ef5218, 0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8,
    0x19a4c116b8d2d0c8, 0x1e376c085141ab53, 0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8,
    0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373, 0x682e6ff3d6b2b8a3,
    0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
    0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b,
    0xca273eceea26619c, 0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178,
    0x06f067aa72176fba, 0x0a637dc5a2c898a6, 0x113f9804bef90dae, 0x1b710b35131c471b,
    0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc, 0x431d67c49c100d4c,
    0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817]

class SHA512 : Hash {
    private var H: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64)
    private var nextMessageBlock: [UInt8] = []
    // the message length is 128 bit long and represented as a tuple (hi, lo)
    private var messageLength: (UInt64, UInt64) = (0, 0)
    
    required init() {
        self.H = (
            0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
            0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179
        )
    }
    
    fileprivate init(H: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64)) {
        self.H = H
    }
    
    class func hash(_ m: [UInt8]) -> [UInt8] {
        let sha = self.init()
        sha.update(m)
        return sha.finalize()
    }
    
    private func updateWithBlock(_ m: [UInt8]) {
        var m = m
        var W = [UInt64](repeating: 0, count: 80)
        
        var a = H.0
        var b = H.1
        var c = H.2
        var d = H.3
        var e = H.4
        var f = H.5
        var g = H.6
        var h = H.7
        
        let blockLength = type(of: self).blockLength

        m.withUnsafeMutableBufferPointer {
            let M = UnsafeRawPointer($0.baseAddress!).bindMemory(to: UInt64.self, capacity: blockLength/8)
            
            var T1: UInt64
            var T2: UInt64
            
            for t in 0..<80 {
                W[t] = (t < 16) ? M[t].byteSwapped : sigma1(W[t-2]) &+ W[t-7] &+ sigma0(W[t-15]) &+ W[t-16]
                
                T1 = h &+ Sigma1(e) &+ Ch(e, f, g) &+ K[t] &+ W[t]
                T2 = Sigma0(a) &+ Maj(a, b, c)
                h = g
                g = f
                f = e
                e = d &+ T1
                d = c
                c = b
                b = a
                a = T1 &+ T2
            }
        }
        
        H.0 = a &+ H.0
        H.1 = b &+ H.1
        H.2 = c &+ H.2
        H.3 = d &+ H.3
        H.4 = e &+ H.4
        H.5 = f &+ H.5
        H.6 = g &+ H.6
        H.7 = h &+ H.7
    }
    
    static var blockLength: Int {
        return 1024/8
    }
    
    func update(_ m: [UInt8]) {
        nextMessageBlock.append(contentsOf: m)
        
        let (newMessageLength, overflow) = messageLength.1.addingReportingOverflow(UInt64(m.count))
        messageLength.1 = newMessageLength
        if overflow {
            messageLength.0 += 1
        }
        
        let blockLength = type(of: self).blockLength
        while nextMessageBlock.count >= blockLength {
            let messageBlock = [UInt8](nextMessageBlock.prefix(blockLength))
            nextMessageBlock.removeFirst(blockLength)
            updateWithBlock(messageBlock)
        }
    }
    
    func finalize() -> [UInt8] {
        let blockLength = type(of: self).blockLength
        precondition(nextMessageBlock.count <= blockLength)
        
        if nextMessageBlock.count < blockLength {
            SHA512.padMessage(&nextMessageBlock, blockLength: blockLength, messageLength: messageLength)
            
            if nextMessageBlock.count > blockLength {
                let messageBlock = [UInt8](nextMessageBlock.prefix(blockLength))
                nextMessageBlock.removeFirst(blockLength)
                updateWithBlock(messageBlock)
            }
        }
        
        updateWithBlock(nextMessageBlock)
        nextMessageBlock = []
        
        return (
            H.0.bigEndianBytes +
                H.1.bigEndianBytes +
                H.2.bigEndianBytes +
                H.3.bigEndianBytes +
                H.4.bigEndianBytes +
                H.5.bigEndianBytes +
                H.6.bigEndianBytes +
                H.7.bigEndianBytes
        )
    }
    
    static func padMessage(_ messageBlock: inout [UInt8], blockLength: Int, messageLength: (UInt64, UInt64)) {
        // pad the message
        var paddingBytes = 111 - messageBlock.count
        if paddingBytes < 0 {
            paddingBytes += blockLength
        }
        
        messageBlock.append(0x80)
        messageBlock.append(contentsOf: [UInt8](repeating: 0, count: paddingBytes))
        messageBlock.append(contentsOf: UInt64(messageLength.0 * 8).bigEndianBytes)
        messageBlock.append(contentsOf: UInt64(messageLength.1 * 8).bigEndianBytes)
    }
}

class SHA384 : SHA512
{
    required init()
    {
        super.init(H: (
            0xcbbb9d5dc1059ed8, 0x629a292a367cd507, 0x9159015a3070dd17, 0x152fecd8f70e5939,
            0x67332667ffc00b31, 0x8eb44a8768581511, 0xdb0c2e0d64f98fa7, 0x47b5481dbefa4fa4
        ))
    }
    
    override func finalize() -> [UInt8] {
        return [UInt8](super.finalize().prefix(384/8))
    }
}