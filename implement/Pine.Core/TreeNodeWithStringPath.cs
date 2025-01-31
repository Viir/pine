using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;

namespace Pine.Core;

public abstract record TreeNodeWithStringPath : IEquatable<TreeNodeWithStringPath>
{
    public record BlobNode : TreeNodeWithStringPath
    {
        private readonly int slimHashCode;

        public ReadOnlyMemory<byte> Bytes { get; }

        public BlobNode(ReadOnlyMemory<byte> bytes)
        {
            Bytes = bytes;

            var hash = new HashCode();

            hash.AddBytes(bytes.Span);

            slimHashCode = hash.ToHashCode();
        }

        public virtual bool Equals(BlobNode? other)
        {
            if (other is null)
                return false;

            return
                slimHashCode == other.slimHashCode &&
                Bytes.Span.SequenceEqual(other.Bytes.Span);
        }

        public override int GetHashCode() => slimHashCode;
    }

    public record TreeNode : TreeNodeWithStringPath
    {
        private readonly int slimHashCode;

        public IReadOnlyList<(string name, TreeNodeWithStringPath component)> Elements { get; }

        public TreeNode(IReadOnlyList<(string name, TreeNodeWithStringPath component)> elements)
        {
            Elements = elements;

            var hash = new HashCode();

            foreach (var item in elements)
            {
                hash.Add(item.GetHashCode());
            }

            slimHashCode = hash.ToHashCode();
        }

        public virtual bool Equals(TreeNode? other)
        {
            if (other is null)
                return false;

            return
                slimHashCode == other.slimHashCode &&
                Elements.Count == other.Elements.Count &&
                Elements.SequenceEqual(other.Elements);
        }

        public override int GetHashCode() => slimHashCode;
    }

    public static readonly IComparer<(string name, TreeNodeWithStringPath component)> TreeEntryDefaultComparer = new TreeEntryDefaultComparerClass();

    public static TreeNodeWithStringPath Blob(ReadOnlyMemory<byte> blobContent) =>
        new BlobNode(blobContent);

    public static TreeNodeWithStringPath SortedTree(IReadOnlyList<(string name, TreeNodeWithStringPath component)> treeContent) =>
        Sort(NonSortedTree(treeContent));

    public static TreeNodeWithStringPath NonSortedTree(IReadOnlyList<(string name, TreeNodeWithStringPath component)> treeContent) =>
        new TreeNode(treeContent);

    public static readonly TreeNodeWithStringPath EmptyTree = new TreeNode([]);


    public IEnumerable<(IImmutableList<string> path, ReadOnlyMemory<byte> blobContent)> EnumerateBlobsTransitive() =>
        this switch
        {
            BlobNode blob => [(ImmutableList<string>.Empty, blob.Bytes)],

            TreeNode tree => tree.Elements.SelectMany(treeEntry =>
            treeEntry.component.EnumerateBlobsTransitive()
            .Select(child => (child.path.Insert(0, treeEntry.name), child.blobContent)))
            .ToImmutableList(),

            _ => throw new NotImplementedException()
        };

    public TreeNodeWithStringPath? GetNodeAtPath(IReadOnlyList<string> path)
    {
        if (path.Count == 0)
            return this;

        var pathFirstElement = path[0];

        return
            this switch
            {
                TreeNode tree => tree.Elements
                .Where(treeNode => treeNode.name == pathFirstElement)
                .Select(treeNode => treeNode.component.GetNodeAtPath(path.Skip(1).ToImmutableList()))
                .FirstOrDefault(),

                _ => null
            };
    }

    public TreeNodeWithStringPath? RemoveNodeAtPath(IReadOnlyList<string> path)
    {
        if (path.Count == 0)
            return null;

        if (this is not TreeNode tree)
            return null;

        var pathFirstElement = path[0];

        var treeContent =
            tree.Elements.SelectMany(treeNode =>
            {
                if (treeNode.name != pathFirstElement)
                    return ImmutableList.Create(treeNode);

                if (path.Count == 1)
                    return [];

                var componentAfterRemoval =
                    treeNode.component.RemoveNodeAtPath(path.Skip(1).ToImmutableArray());

                if (componentAfterRemoval == null)
                    return [];

                return ImmutableList.Create((treeNode.name, componentAfterRemoval));
            }).ToImmutableList();

        return SortedTree(treeContent);
    }

    public TreeNodeWithStringPath SetNodeAtPathSorted(IReadOnlyList<string> path, TreeNodeWithStringPath node)
    {
        if (path.Count is 0)
            return node;

        var pathFirstElement = path[0];

        var childNodeBefore = GetNodeAtPath([pathFirstElement]);

        var childNode =
            (childNodeBefore ?? EmptyTree).SetNodeAtPathSorted(path.Skip(1).ToImmutableList(), node);

        var treeEntries =
            (this switch
            {
                TreeNode tree => tree.Elements,
                _ => []
            })
            .Where(treeNode => treeNode.name != pathFirstElement)
            .Concat([(pathFirstElement, childNode)])
            .Order(TreeEntryDefaultComparer)
            .ToImmutableList();

        return SortedTree(treeEntries);
    }

    public static TreeNodeWithStringPath MergeBlobs(
        TreeNodeWithStringPath left,
        TreeNodeWithStringPath right) =>
        right.EnumerateBlobsTransitive()
        .Aggregate(left, (acc, blob) => acc.SetNodeAtPathSorted(blob.path, Blob(blob.blobContent)));


    public static TreeNodeWithStringPath FilterNodesByPath(
        TreeNodeWithStringPath node,
        Func<IReadOnlyList<string>, bool> pathFilter,
        IReadOnlyList<string>? currentPrefix = null) =>
        node switch
        {
            BlobNode blob => blob,

            TreeNode tree =>
            new TreeNode(
                tree.Elements
                .Where(treeNode => pathFilter([.. (currentPrefix ?? []), treeNode.name]))
                .Select(treeNode => (treeNode.name,
                FilterNodesByPath(
                    treeNode.component,
                    pathFilter,
                    currentPrefix: [.. currentPrefix ?? [], treeNode.name])))
                .ToImmutableList()),

            _ =>
            throw new NotImplementedException(
                "Unexpected node type: " + node.GetType())
        };

    public static TreeNodeWithStringPath? RemoveEmptyNodes(TreeNodeWithStringPath node)
    {
        if (node is BlobNode)
            return node;

        if (node is TreeNode tree)
        {
            IReadOnlyList<(string name, TreeNodeWithStringPath component)> newElements =
                [..tree.Elements
                .Select(e => (e.name, component: RemoveEmptyNodes(e.component)))
                .Where(e => e.component is not null)
                ];

            if (newElements.Count is 0)
                return null;

            return new TreeNode(newElements);
        }

        throw new NotImplementedException(
            "Unexpected node type: " + node.GetType());
    }

    public static TreeNodeWithStringPath Sort(TreeNodeWithStringPath node) =>
        node switch
        {
            BlobNode _ => node,
            TreeNode tree =>
            new TreeNode(tree.Elements.Order(TreeEntryDefaultComparer).Select(child => (child.name, Sort(child.component))).ToImmutableList()),

            _ => throw new NotImplementedException()
        };

    public T Map<T>(
        Func<ReadOnlyMemory<byte>, T> fromBlob,
        Func<IReadOnlyList<(string itemName, TreeNodeWithStringPath itemValue)>, T> fromTree) =>
        this switch
        {
            TreeNode tree => fromTree(tree.Elements),

            BlobNode blob => fromBlob(blob.Bytes),

            _ => throw new NotImplementedException()
        };

    private class TreeEntryDefaultComparerClass : IComparer<(string name, TreeNodeWithStringPath component)>
    {
        public int Compare((string name, TreeNodeWithStringPath component) x, (string name, TreeNodeWithStringPath component) y)
        {
            return string.CompareOrdinal(x.name, y.name);
        }
    }
}

