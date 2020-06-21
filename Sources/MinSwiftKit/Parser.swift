import Foundation
import SwiftSyntax

class Parser: SyntaxVisitor {
    private(set) var tokens: [TokenSyntax] = []
    private var index = 0
    private(set) var currentToken: TokenSyntax!

    // MARK: Practice 1

    override func visit(_ token: TokenSyntax) {
        tokens.append(token)
    }

    @discardableResult
    func read() -> TokenSyntax {
        let index = currentToken.flatMap(tokens.firstIndex(of:)) ?? -1
        currentToken = tokens[index + 1]
        return currentToken
    }

    func peek(_ n: Int = 0) -> TokenSyntax {
        let index = tokens.firstIndex(of: currentToken) ?? 0
        return tokens[index + n + 1]
    }

    // MARK: Practice 2

    private func extractNumberLiteral(from token: TokenSyntax) -> Double? {
        switch token.tokenKind {
        case .integerLiteral(let literal), .floatingLiteral(let literal):
            return Double(literal)
        default: return nil
        }
    }

    func parseNumber() -> Node {
        guard let value = extractNumberLiteral(from: currentToken) else {
            fatalError("any number is expected")
        }
        read() // eat literal
        return NumberNode(value: value)
    }

    func parseIdentifierExpression() -> Node {
        guard case .identifier(let id) = currentToken.tokenKind else {
            fatalError("any identifier is expected")
        }
        read()
        
        guard case .leftParen = currentToken.tokenKind else {
            return VariableNode(identifier: id)
        }
        read() // eat `(`
        
        var args = [CallExpressionNode.Argument]()
        while currentToken.tokenKind != .rightParen {
            let label: String?
            switch (currentToken.tokenKind, peek().tokenKind) {
            case (.identifier(let name), .colon):
                read(); read()
                label = name
            case (_, _): label = nil
            }
            
            args.append(.init(label: label, value: parseExpression()!))
            guard case .comma = currentToken.tokenKind else { break }
            read()
        }
        read()  // eat `)`
        
        return CallExpressionNode(callee: id, arguments: args)
    }

    // MARK: Practice 3

    func extractBinaryOperator(from token: TokenSyntax) -> BinaryExpressionNode.Operator? {
        switch token.tokenKind {
        case .spacedBinaryOperator(let s), .unspacedBinaryOperator(let s):
            switch s {
            case "+":  return .addition
            case "-":  return .subtraction
            case "*":  return .multication
            case "/":  return .division
            case "<":  return .lessThan
            case ">":  return .greaterThan
            case "==": return .equal
            default:   return nil
            }
        case .prefixOperator, .postfixOperator:
            return nil
        default:
            return nil
        }
    }

    private func parseBinaryOperatorRHS(expressionPrecedence: Int, lhs: Node?) -> Node? {
        var currentLHS: Node? = lhs
        while true {
            let binaryOperator = extractBinaryOperator(from: currentToken!)
            let operatorPrecedence = binaryOperator?.precedence ?? -1

            // Compare between operatorPrecedence and expressionPrecedence
            if expressionPrecedence > operatorPrecedence { // TODO
                return currentLHS
            }

            read() // eat binary operator
            guard var rhs = parsePrimary() else { return nil }

            // If binOperator binds less tightly with RHS than the operator after RHS, let
            // the pending operator take RHS as its LHS.
            let nextPrecedence = extractBinaryOperator(from: currentToken!)?.precedence ?? -1
            if operatorPrecedence < nextPrecedence { // TODO
                // Search next RHS from current RHS
                // next precedence will be `operatorPrecedence + 1`
                // TODO rhs = XXX
                rhs = parseBinaryOperatorRHS(expressionPrecedence: nextPrecedence, lhs: rhs) ?? rhs
            }

            // TODO update current LHS
            // currentLHS = XXX
            currentLHS = BinaryExpressionNode(binaryOperator!, lhs: currentLHS!, rhs: rhs)
        }
    }

    // MARK: Practice 4

    func parseFunctionDefinitionArgument() -> FunctionNode.Argument {
        switch (currentToken.tokenKind, read().tokenKind, read().tokenKind, read().tokenKind) {
        case (.identifier(let name), .colon, .identifier, _):
            return FunctionNode.Argument(label: name, variableName: name)
        case (.identifier(let label), .identifier(let name), .colon, .identifier):
            read()
            return FunctionNode.Argument(label: label, variableName: name)
        case (.wildcardKeyword, .identifier(let name), .colon, .identifier):
            read()
            return FunctionNode.Argument(label: nil, variableName: name)
        default: fatalError("invalid argument")
        }
    }

    func parseFunctionDefinition() -> Node {
        guard case .funcKeyword = currentToken.tokenKind,
            case .identifier(let name) = read().tokenKind,
            case .leftParen = read().tokenKind else {
            fatalError("expected function")
        }
        read(for: .leftParen)
        
        var args = [FunctionNode.Argument]()
        while currentToken.tokenKind != .rightParen {
            args.append(parseFunctionDefinitionArgument())
            guard case .comma = currentToken.tokenKind else { break }
            read(for: .comma)
        }
        read(for: .rightParen)
        
        var returnType: Type = .void
        if case .arrow = currentToken.tokenKind,
            case .identifier(let typeName) = peek().tokenKind {
            read(); read()
            switch typeName {
            case "Int", "Int64": returnType = .int
            case "Double": returnType = .double
            case "Void": returnType = .void
            case _: ()
            }
        }
        
        read(for: .leftBrace)
        let body = parseExpression()
        read(for: .rightBrace)
        
        return FunctionNode(name: name, arguments: args, returnType: returnType, body: body!)
    }

    // MARK: Practice 7

    func parseIfElse() -> Node {
        read(for: .ifKeyword)
        guard let condition = parseExpression() else {
            fatalError("if expression need condition")
        }
        read(for: .leftBrace)
        guard let thenBlock = parseExpression() else {
            fatalError("if expression need then block")
        }
        read(for: .rightBrace)
        
        let elseBlock: Node?
        if case .elseKeyword = currentToken.tokenKind {
            read(for: .elseKeyword)
            
            switch currentToken.tokenKind {
            case .leftBrace:
                read(for: .leftBrace)
                elseBlock = parseExpression()
                read(for: .rightBrace)
            case .ifKeyword:
                elseBlock = parseIfElse()
            default: fatalError("else expression need block")
            }
        } else {
            elseBlock = nil
        }

        return IfElseNode(condition: condition, then: thenBlock, else: elseBlock)
    }

    // PROBABLY WORKS WELL, TRUST ME

    func parse() -> [Node] {
        var nodes: [Node] = []
        read()
        while true {
            switch currentToken.tokenKind {
            case .eof:
                return nodes
            case .funcKeyword:
                let node = parseFunctionDefinition()
                nodes.append(node)
            default:
                if let node = parseTopLevelExpression() {
                    nodes.append(node)
                    break
                } else {
                    read()
                }
            }
        }
        return nodes
    }

    private func parsePrimary() -> Node? {
        switch currentToken.tokenKind {
        case .identifier:
            return parseIdentifierExpression()
        case .integerLiteral, .floatingLiteral:
            return parseNumber()
        case .leftParen:
            return parseParen()
        case .funcKeyword:
            return parseFunctionDefinition()
        case .returnKeyword:
            return parseReturn()
        case .ifKeyword:
            return parseIfElse()
        case .eof:
            return nil
        case .rightBrace:
            return VoidNode()
        default:
            fatalError("Unexpected token \(currentToken.tokenKind)(\(currentToken.text))")
        }
    }

    func parseExpression() -> Node? {
        guard let lhs = parsePrimary() else {
            return nil
        }
        return parseBinaryOperatorRHS(expressionPrecedence: 0, lhs: lhs)
    }

    private func parseReturn() -> Node {
        guard case .returnKeyword = currentToken.tokenKind else {
            fatalError("returnKeyword is expected but received \(currentToken.tokenKind)")
        }
        read() // eat return
        if let expression = parseExpression() {
            return ReturnNode(body: expression)
        } else {
            // return nothing
            return ReturnNode(body: nil)
        }
    }

    private func parseParen() -> Node? {
        read(for: .leftParen)
        guard let v = parseExpression() else { return nil }
        read(for: .rightParen)
        return v
    }

    private func parseTopLevelExpression() -> Node? {
        if let expression = parseExpression() {
            // we treat top level expressions as anonymous functions
            let anonymousPrototype = FunctionNode(name: "main", arguments: [], returnType: .int, body: expression)
            return anonymousPrototype
        }
        return nil
    }
}

private extension BinaryExpressionNode.Operator {
    var precedence: Int {
        switch self {
        case .addition, .subtraction: return 20
        case .multication, .division: return 40
        case .lessThan, .greaterThan, .equal: return 10
        }
    }
}


extension Parser {
    func read(for kind: TokenKind) {
        if case kind = currentToken.tokenKind {
            read()
        } else {
            fatalError("expected '\(kind)'")
        }
    }
}
