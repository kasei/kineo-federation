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
