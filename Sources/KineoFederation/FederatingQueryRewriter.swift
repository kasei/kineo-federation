//
//  FederatingQueryRewriter.swift
//  CryptoSwift
//
//  Created by Gregory Todd Williams on 8/9/18.
//

import Foundation
import SPARQLSyntax
import Kineo

public protocol AvailabilityOracle {
    func algebra(_ algebra: Algebra, availableAt endpoint: URL) -> Bool
}

public class NullAvailabilityOracle : AvailabilityOracle {
    public func algebra(_ algebra: Algebra, availableAt endpoint: URL) -> Bool {
        return true
    }
}

public class CachingAskAvailabilityOracle : AvailabilityOracle {
    var existsCache: [URL:[Algebra:Bool]]
    public init() {
        existsCache = [:]
    }
    
    public func algebra(_ algebra: Algebra, availableAt endpoint: URL) -> Bool {
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
    
    public init(oracle: AvailabilityOracle? = nil) {
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
        
        for _ in 1..<5 {
            // TODO: this is a hack because rewriting happend top-to-bottom, but join merging needs to happen bottom-to-top
            query = try query.rewrite(FederatingQueryRewriter.mergeServiceJoins)
        }
        query = try query.rewrite(FederatingQueryRewriter.reorderServiceJoins)
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

