import Foundation
import LLVM

@discardableResult
func generateIRValue(from node: Node, with context: BuildContext) -> IRValue {
    switch node {
    case let numberNode as NumberNode:
        return Generator<NumberNode>(node: numberNode).generate(with: context)
    case let binaryExpressionNode as BinaryExpressionNode:
        return Generator<BinaryExpressionNode>(node: binaryExpressionNode).generate(with: context)
    case let variableNode as VariableNode:
        return Generator<VariableNode>(node: variableNode).generate(with: context)
    case let functionNode as FunctionNode:
        return Generator<FunctionNode>(node: functionNode).generate(with: context)
    case let callExpressionNode as CallExpressionNode:
        return Generator<CallExpressionNode>(node: callExpressionNode).generate(with: context)
    case let ifElseNode as IfElseNode:
        return Generator<IfElseNode>(node: ifElseNode).generate(with: context)
    case let returnNode as ReturnNode:
        return Generator<ReturnNode>(node: returnNode).generate(with: context)
    default:
        fatalError("Unknown node type \(type(of: node))")
    }
}

private protocol GeneratorProtocol {
    associatedtype NodeType: Node
    var node: NodeType { get }
    func generate(with: BuildContext) -> IRValue
    init(node: NodeType)
}

private struct Generator<NodeType: Node>: GeneratorProtocol {
    func generate(with context: BuildContext) -> IRValue {
        fatalError("Not implemented")
    }

    let node: NodeType
    init(node: NodeType) {
        self.node = node
    }
}

// MARK: Practice 6

extension Generator where NodeType == NumberNode {
    func generate(with context: BuildContext) -> IRValue {
        FloatType.double.constant(node.value)
    }
}

extension Generator where NodeType == VariableNode {
    func generate(with context: BuildContext) -> IRValue {
        guard let variable = context.namedValues[node.identifier] else {
            fatalError("Undefined variable named \(node.identifier)")
        }
        return variable
    }
}

extension Generator where NodeType == BinaryExpressionNode {
    func generate(with context: BuildContext) -> IRValue {
        let lhs = generateIRValue(from: node.lhs, with: context)
        let rhs = generateIRValue(from: node.rhs, with: context)
        switch node.operator {
        case .addition:    return context.builder.buildAdd(lhs, rhs, name: "AdditionNode")
        case .subtraction: return context.builder.buildSub(lhs, rhs, name: "SubtractionNode")
        case .multication: return context.builder.buildMul(lhs, rhs, name: "multmp")
        case .division:    return context.builder.buildDiv(lhs, rhs, name: "DivisionNode")
        case .equal:
            let bool = context.builder.buildFCmp(lhs, rhs, .orderedEqual, name: "cmptmp")
            return context.builder.buildIntToFP(bool, type: FloatType.double, signed: true)
        case .lessThan:
            let bool = context.builder.buildFCmp(lhs, rhs, .orderedLessThan, name: "cmptmp")
            return context.builder.buildIntToFP(bool, type: FloatType.double, signed: true)
        case .greaterThan:
            let bool = context.builder.buildFCmp(lhs, rhs, .orderedGreaterThan, name: "cmptmp")
            return context.builder.buildIntToFP(bool, type: FloatType.double, signed: true)
        }
    }
}

extension Generator where NodeType == FunctionNode {
    func generate(with context: BuildContext) -> IRValue {
        let argTypes: [IRType] = [FloatType.double]
        let returnType: IRType = FloatType.double
        let funcType = FunctionType(argTypes: argTypes, returnType: returnType)
        let function = context.builder.addFunction(node.name, type: funcType)
        
        let entryBasicBlock = function.appendBasicBlock(named: "entry")
        context.builder.positionAtEnd(of: entryBasicBlock)
        
        context.namedValues.removeAll()
        for i in node.arguments.indices {
            let name = node.arguments[i].variableName
            context.namedValues[name] = function.parameters[i]
        }
        
        let functionBody: IRValue = generateIRValue(from: node.body, with: context)
        context.builder.buildRet(functionBody)
        return functionBody
    }
}

extension Generator where NodeType == CallExpressionNode {
    func generate(with context: BuildContext) -> IRValue {
        let function = context.module.function(named: node.callee)!
        let args: [IRValue] = node.arguments.map { generateIRValue(from: $0.value, with: context) }
        return context.builder.buildCall(function, args: args, name: "calltmp")
    }
}

extension Generator where NodeType == IfElseNode {
    func generate(with context: BuildContext) -> IRValue {
        let condition = generateIRValue(from: node.condition, with: context)
        let bool = context.builder.buildFCmp(
            condition, FloatType.double.constant(0), .orderedNotEqual, name: "ifcond")
        
        let function = context.builder.insertBlock!.parent!
        let local = context.builder.buildAlloca(type: FloatType.double, name: "local")
        
        let thenBasicBlock = function.appendBasicBlock(named: "then")
        let elseBasicBlock = function.appendBasicBlock(named: "else")
        let mergeBasicBlock = function.appendBasicBlock(named: "merge")
        
        context.builder.buildCondBr(condition: bool, then: thenBasicBlock, else: elseBasicBlock)
        context.builder.positionAtEnd(of: thenBasicBlock)
        
        let thenVal = generateIRValue(from: node.then, with: context)
        context.builder.buildBr(mergeBasicBlock)
        
        
        context.builder.positionAtEnd(of: elseBasicBlock)
        
        let elseVal = generateIRValue(from: node.else!, with: context)
        context.builder.buildBr(mergeBasicBlock)
        
        context.builder.positionAtEnd(of: mergeBasicBlock)
        
        let phi = context.builder.buildPhi(FloatType.double, name: "phi")
        phi.addIncoming([(thenVal, thenBasicBlock), (elseVal, elseBasicBlock)])
        context.builder.buildStore(phi, to: local)
        
        return phi
    }
}

extension Generator where NodeType == ReturnNode {
    func generate(with context: BuildContext) -> IRValue {
        if let body = node.body {
            let returnValue = MinSwiftKit.generateIRValue(from: body, with: context)
            return returnValue
        } else {
            return VoidType().null()
        }
    }
}
