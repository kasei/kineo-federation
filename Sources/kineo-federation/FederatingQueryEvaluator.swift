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

protocol AvailabilityOracle {
    func algebra(_ algebra: Algebra, availableAt endpoint: URL) -> Bool
}

class NullAvailabilityOracle : AvailabilityOracle {
    func algebra(_ algebra: Algebra, availableAt endpoint: URL) -> Bool {
        return true
    }
}

public class CachingAskAvailabilityOracle : AvailabilityOracle {
    var existsCache: [URL:[Algebra:Bool]]
    init() {
        existsCache = [:]
    }
    
    func algebra(_ algebra: Algebra, availableAt endpoint: URL) -> Bool {
        if let e = existsCache[endpoint, default: [:]][algebra] {
            return e
        } else {
            switch algebra {
            case .triple(let tp):
                if case .bound(let t) = tp.predicate {
                    let e = predicate(t, existsInEndpoint: endpoint)
                    existsCache[endpoint, default: [:]][algebra] = e
                    return e
                }
            default:
                break
            }
            print("Is \(algebra) possibly available from \(endpoint)?")
            existsCache[endpoint, default: [:]][algebra] = true // TODO
            return true
        }
    }

    private func predicate(_ pred: Term, existsInEndpoint endpoint: URL) -> Bool {
        print("Is predicate \(pred) available in \(endpoint)?")
        let sparql = "ASK { [] \(pred) [] }"
        let client = SPARQLClient(endpoint: endpoint)
        do {
            let result = try client.execute(sparql)
            switch result {
            case .boolean(let b):
                print("-> \(b ? "yes" : "no")")
                return b
            default:
                return true
            }
        } catch {
            print("*** \(error)")
            return true
        }
    }
}

open class FederatingQueryRewriter {
    var oracle: AvailabilityOracle
    
    init(oracle: AvailabilityOracle? = nil) {
        self.oracle = oracle ?? CachingAskAvailabilityOracle()
    }
    public func federatedEquavalent(for query: Query, endpoints: [URL]) throws -> Query {
        let rewriter = SPARQLQueryRewriter()
        let cachingOracle = self.oracle
        let addServiceCalls = constructServiceCallInsertionRewriter(endpoints: endpoints, algebraOracle: cachingOracle)
        var query = try rewriter.simplify(query: query)
            .rewrite(addServiceCalls)
        query = try query.rewrite(FederatingQueryRewriter.pushdownJoins)
        query = try rewriter.simplify(query: query)
        
        query = try query
            .rewrite(FederatingQueryRewriter.mergeServiceJoins)
            .rewrite(FederatingQueryRewriter.reorderServiceJoins)
        query = try rewriter.simplify(query: query)
        return query
    }

    private func constructServiceCallInsertionRewriter(endpoints: [URL], algebraOracle oracle: AvailabilityOracle) -> (Algebra) throws -> RewriteStatus<Algebra> {
        return { (a: Algebra) throws -> RewriteStatus<Algebra> in
            switch a {
            case .service(_):
                return .keep
            case .bgp(let tps):
                let a : Algebra = tps.reduce(.joinIdentity) { .innerJoin($0, .triple($1)) }
                return .rewriteChildren(a)
            case .triple(_), .quad(_), .path(_):
                let services = endpoints.compactMap { (u) -> Algebra? in
                    if oracle.algebra(a, availableAt: u) {
                        return .service(u, a, false)
                    } else {
                        return nil
                    }
                }
                let u : Algebra = services.reduce(.unionIdentity) { .union($0, $1) }
                return .rewrite(u)
            default:
                return .rewriteChildren(a)
            }
        }
    }

    private static func reorderServiceJoins(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
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

    private static func mergeServiceJoins(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
        switch algebra {
        case let .innerJoin(.service(a, lhs, ls), .service(b, rhs, rs)) where a == b:
            return .rewrite(.service(a, .innerJoin(lhs, rhs), ls || rs))
        default:
            return .rewriteChildren(algebra)
        }
    }

    private static func pushdownJoins(_ algebra: Algebra) throws -> RewriteStatus<Algebra> {
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
        let rewriter = FederatingQueryRewriter()
        let query = try rewriter.federatedEquavalent(for: original, endpoints: endpoints)
        
//        print("============================================================")
//        print(query.serialize())
        return try evaluate(query: query, activeGraph: nil)
    }

    public func evaluate(algebra: Algebra, endpoint: URL, silent: Bool, activeGraph: Term) throws -> AnyIterator<TermResult> {
        // TODO: improve this implementation (copied from SimpleQueryEvaluatorProtocol) to allow service calls to be fired in parallel and cached in cases where a pattern is repeated in the algebra tree
        // customizable parameters:
        // N - TOTAL number of requests that can be executed concurrently
        // M - number of requests PER ENDPOINT that can be executed concurrently
        //
        // Allow a pre-execution algebra tree walk to identify the service calls, and queue requests for execution;
        // then allow execution-time code to access the content that comes back.
        // For a more involved implementation, allow query execution to be push driven (bottom-up)
        // instead of pull driven (top-down), evaluating query operators as each new service call
        // becomes available.
        
        let client = SPARQLClient(endpoint: endpoint, silent: silent)
        do {
            let s = SPARQLSerializer(prettyPrint: true)
            guard let q = try? Query(form: .select(.star), algebra: algebra) else {
                throw QueryError.evaluationError("Failed to serialize SERVICE algebra into SPARQL string")
            }
            let tokens = try q.sparqlTokens()
            let query = s.serialize(tokens)
            let r = try client.execute(query)
            switch r {
            case let .bindings(_, seq):
                return AnyIterator(seq.makeIterator())
            default:
                throw QueryError.evaluationError("SERVICE request did not return bindings")
            }
        } catch let e {
            throw QueryError.evaluationError("SERVICE error: \(e)")
        }
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

