using Microsoft.VisualStudio.TestTools.UnitTesting;
using Pine.Core;
using System.Collections.Generic;
using FluentAssertions;
using FluentAssertions.Execution;

namespace Pine.UnitTests;

[TestClass]
public class ReusedInstancesTests
{
    [TestMethod]
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
            a.Count.Should().Be(b.Count, "counts should be equal");
        }

        foreach (var kv in a)
        {
            b.Should().ContainKey(kv.Key);
        }
    }
}