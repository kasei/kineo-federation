//
//  Query.swift
//  Kineo
//
//  Created by Gregory Todd Williams on 7/8/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax
import Kineo

public struct FederationQuery : Hashable, Equatable {
    public var base: String?
    public var form: QueryForm
    public var algebra: FederationAlgebra
    public var dataset: Dataset?
    
    public init(form: QueryForm, algebra: FederationAlgebra, dataset: Dataset? = nil, base: String? = nil) throws {
        self.base = base
        self.form = form
        self.algebra = algebra
        self.dataset = dataset
    }
}

public indirect enum FederationAlgebra : Hashable {
    case table([Node], [[Term?]])
    case bgp([TriplePattern])
    case innerJoin(FederationAlgebra, FederationAlgebra)
    case leftOuterJoin(FederationAlgebra, FederationAlgebra, Expression)
    case filter(FederationAlgebra, Expression)
    case union(FederationAlgebra, FederationAlgebra)
    case namedGraph(FederationAlgebra, Node)
    case extend(FederationAlgebra, Expression, String)
    case minus(FederationAlgebra, FederationAlgebra)
    case project(FederationAlgebra, Set<String>)
    case distinct(FederationAlgebra)
    case service(URL, FederationAlgebra, Bool)
    case slice(FederationAlgebra, Int?, Int?)
    case order(FederationAlgebra, [Algebra.SortComparator])
    case path(Node, PropertyPath, Node)
    case aggregate(FederationAlgebra, [Expression], Set<Algebra.AggregationMapping>)
    case subquery(FederationQuery)
}

// swiftlint:disable cyclomatic_complexity
// swiftlint:disable:next type_body_length
open class FederatingQueryEvaluator: SimpleQueryEvaluatorProtocol {
    public var dataset: Dataset
    public var ee: ExpressionEvaluator
    public let supportedLanguages: [QueryLanguage] = [.sparqlQuery10, .sparqlQuery11]
    public let supportedFeatures: [QueryEngineFeature] = []
    public var verbose: Bool
    private var freshVarNumber : Int
    private var endpoints: [URL]
    
    public init(endpoints: [URL], verbose: Bool) {
        self.verbose = verbose
        self.endpoints = endpoints
        self.freshVarNumber = 0
        self.verbose = false
        self.ee = ExpressionEvaluator()
        self.dataset = Dataset()
    }
    
    public func freshVariable() -> Node {
        let n = freshVarNumber
        freshVarNumber += 1
        return .variable(".v\(n)", binding: true)
    }
    
    public func effectiveVersion(matching query: Query) throws -> Version? {
        return nil
    }
    
    public func effectiveVersion(matching algebra: Algebra, activeGraph: Term) throws -> Version? {
        return nil
    }
    
    public func evaluateGraphTerms(in: Term) -> AnyIterator<Term> {
        fatalError("evaluateGraphTerms(in:) should never be called after query rewriting")
    }
    
    public func triples(describing term: Term) throws -> AnyIterator<Triple> {
        fatalError("TODO: implement triples(describing:)")
    }

    public func evaluate(quad: QuadPattern) throws -> AnyIterator<TermResult> {
        fatalError("evaluate(quad:) should never be called after query rewriting")
    }

    public func evaluate(algebra: Algebra, inGraph: Node) throws -> AnyIterator<TermResult> {
        fatalError("TODO: implement evaluate(algebra:inGraph:)")
    }

    public func evaluate(query original: Query) throws -> QueryResult<[TermResult], [Triple]> {
        let rewriter = SPARQLQueryRewriter()
        let addServiceCalls = constructServiceCallInsertionRewriter()
        var query = try rewriter.simplify(query: original)
            .rewrite(addServiceCalls)
        
        for _ in 1...4 { // TODO: fix this whenever query rewriting can handle bottom-up rewriting rules
            query = try query.rewrite(pushdownJoins)
        }

        for _ in 1...4 { // TODO: fix this whenever query rewriting can handle bottom-up rewriting rules
            query = try rewriter.simplify(query: query)
        }
        
        query = try query.rewrite(mergeServiceJoins)
        query = try query.rewrite(reorderServiceJoins)

        for _ in 1...4 { // TODO: fix this whenever query rewriting can handle bottom-up rewriting rules
            query = try rewriter.simplify(query: query)
        }
        return try evaluate(query: query, activeGraph: nil)
    }

    private func constructServiceCallInsertionRewriter() -> (Algebra) throws -> RewriteStatus<Algebra> {
        let e = self.endpoints
        return { (a: Algebra) throws -> RewriteStatus<Algebra> in
            switch a {
            case .bgp(let tps):
                let a : Algebra = tps.reduce(.joinIdentity) { .innerJoin($0, .triple($1)) }
                return .rewriteChildren(a)
            case .triple(_), .quad(_), .path(_):
                let services = e.map { (u) -> Algebra in Algebra.service(u, a, false) }
                let u : Algebra = services.reduce(.unionIdentity) { .union($0, $1) }
                return .rewrite(u)
            default:
                return .rewriteChildren(a)
            }
        }
    }
}

private func reorderServiceJoins(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
    switch algebra {
    case .union(_, _):
        let branches = algebra.unionBranches!.sorted { $0.serviceCount <= $1.serviceCount }
        let f = branches.first!
        let u = branches.dropFirst().reduce(f) { .union($0, $1) }
        return .rewrite(u)
    default:
        return .rewriteChildren(algebra)
    }
}

private func mergeServiceJoins(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
    switch algebra {
    case let .innerJoin(.service(a, lhs, ls), .service(b, rhs, rs)) where a == b:
        return .rewrite(.service(a, .innerJoin(lhs, rhs), ls || rs))
    default:
        return .rewriteChildren(algebra)
    }
}

private func pushdownJoins(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
    switch algebra {
    case let .innerJoin(.union(a, b), .union(c, d)):
        return .rewriteChildren(
            .union(
                .union(
                    .innerJoin(a, c),
                    .innerJoin(a, d)
                ),
                .union(
                    .innerJoin(b, c),
                    .innerJoin(b, d)
                )
            )
        )
    case let .innerJoin(.union(a, b), c):
        return .rewriteChildren(.union(.innerJoin(a, c), .innerJoin(b, c)))
    case let .innerJoin(a, .union(b, c)):
        return .rewriteChildren(.union(.innerJoin(a, b), .innerJoin(a, c)))
    default:
        return .rewriteChildren(algebra)
    }
}


extension Algebra {
    var serviceCount: Int {
        var count = 0
        _ = try? self.rewrite({ (a) -> RewriteStatus<Algebra> in
            if case .service(_) = a {
                count += 1
            }
            return .rewriteChildren(a)
        })
        return count
    }
    
    var unionBranches: [Algebra]? {
        guard case let .union(l, r) = self else {
            return nil
        }
        
        let lhs = l.unionBranches ?? [l]
        let rhs = r.unionBranches ?? [r]
        return lhs + rhs
    }
}
