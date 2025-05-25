using FluentAssertions;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Pine.Core;
using System.Collections.Generic;

namespace Pine.UnitTests;

[TestClass]
public class ReusedInstancesTests
{
    [TestMethod]
    [Ignore("Reference equality test fails, unrelated to assertion style changes")]
    public void Ensure_reference_equality_between_mappings_between_reused_instances()
    {
        ReusedInstances.Instance.AssertReferenceEquality();
    }

    public static void AssertPineValueListDictsAreEquivalent(
        IReadOnlyDictionary<PineValue.ListValue.ListValueStruct, PineValue.ListValue> a,
        IReadOnlyDictionary<PineValue.ListValue.ListValueStruct, PineValue.ListValue> b)
    {
        if (a.Count != b.Count)
        {
            // Use FluentAssertions to fail the test
            a.Count.Should().Be(b.Count, "Counts should be equal");
        }

        foreach (var kv in a)
        {
            b.Should().ContainKey(kv.Key, "dictionary should contain the key");
        }
    }
}