using Pine.Core;
using Pine.Json;
using System;
using System.Text.Json.Serialization;

namespace Pine.PineVM;


[JsonConverter(typeof(JsonConverterForChoiceType))]
public abstract record StackInstruction
{
    public static StackInstruction Eval(Expression expression) =>
        new EvalInstruction(expression);

    public static StackInstruction Jump(int offset) =>
        new JumpInstruction(offset);

    public static readonly StackInstruction Return = new ReturnInstruction();

    public record EvalInstruction(
        Expression Expression)
        : StackInstruction;

    public record JumpInstruction(
        int Offset)
        : StackInstruction;

    public record ConditionalJumpInstruction(
        int TrueBranchOffset)
        : StackInstruction;

    public record ReturnInstruction
        : StackInstruction;

    public record CopyLastAssignedInstruction
        : StackInstruction;

    public static StackInstruction TransformExpressionWithOptionalReplacement(
        Func<Expression, Expression> transformExpression,
        StackInstruction instruction)
    {
        switch (instruction)
        {
            case EvalInstruction evalInstruction:

                var newExpression = transformExpression(evalInstruction.Expression);

                return new EvalInstruction(newExpression);

            case JumpInstruction:
                return instruction;

            case ConditionalJumpInstruction:
                return instruction;

            case ReturnInstruction:
                return Return;

            case CopyLastAssignedInstruction:
                return instruction;

            default:
                throw new NotImplementedException(
                    "Unexpected instruction type: " + instruction.GetType().FullName);
        }
    }
}
