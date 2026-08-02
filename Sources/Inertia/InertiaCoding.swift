//
//  InertiaCoding.swift
//  Inertia
//
//  The one place the animation format's encoding is decided.
//

import Foundation
import MessagePack

/// How every Inertia value is turned into bytes, whether it is going to disk or
/// onto the editor channel.
///
/// MessagePack rather than JSON, and the two paths share these coders on
/// purpose: an animation file and a `schema` frame carry the same
/// `InertiaAnimationSchema`, so a format decision made for one is a format
/// decision made for the other. Everything stays `Codable` — the type
/// declarations are the schema, and only the bytes they land in changed.
///
/// The editor uses these rather than importing `MessagePack` itself, so the
/// format is described in one module instead of two that can drift.
public enum InertiaCoding {
    /// The file extension animation files carry, without the dot.
    ///
    /// A shipped animation is `<containerId>.msgpack` in the app's bundle, its
    /// Android assets, or under the React runtime's `baseURL`; a project's own
    /// is `animation.msgpack`.
    public static let fileExtension = "msgpack"

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try MessagePackEncoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try MessagePackDecoder().decode(type, from: data)
    }
}
