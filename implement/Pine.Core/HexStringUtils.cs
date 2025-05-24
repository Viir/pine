using System;

namespace Pine.Core;

/// <summary>
/// Utility methods for working with hexadecimal string representations.
/// </summary>
public static class HexStringUtils
{
    /// <summary>
    /// Converts a byte array to a lowercase hexadecimal string.
    /// </summary>
    /// <param name="bytes">The byte array to convert.</param>
    /// <returns>A lowercase hexadecimal string representation of the byte array.</returns>
    public static string ToHexStringLower(byte[] bytes) =>
        BitConverter.ToString(bytes).Replace("-", "").ToLowerInvariant();

    /// <summary>
    /// Converts a span of bytes to a lowercase hexadecimal string.
    /// </summary>
    /// <param name="bytes">The span of bytes to convert.</param>
    /// <returns>A lowercase hexadecimal string representation of the byte span.</returns>
    public static string ToHexStringLower(ReadOnlySpan<byte> bytes) =>
        BitConverter.ToString(bytes.ToArray()).Replace("-", "").ToLowerInvariant();
}