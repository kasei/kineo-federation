//
//  main.swift
//  kineo-federation
//
//  Created by Gregory Todd Williams on 6/24/16.
//  Copyright © 2016 Gregory Todd Williams. All rights reserved.
//

import Foundation
import SPARQLSyntax
import Kineo
import KineoFederation

/**
 Evaluate the supplied Query against the database's QuadStore and print the results.
 If a graph argument is given, use it as the initial active graph.
 
 - parameter query: The query to evaluate.
 - parameter graph: The graph name to use as the initial active graph.
 - parameter verbose: A flag indicating whether verbose debugging should be emitted during query evaluation.
 */
func query(query: Query, graph: Term? = nil, verbose: Bool) throws -> Int {
    var count       = 0
    let startTime = getCurrentTime()
    let endpoints : [URL] = [URL(string: "http://dbpedia.org/sparql")!, URL(string: "http://example.org/sparql")!]
    let e           = FederatingQueryEvaluator(endpoints: endpoints, verbose: verbose)
    if let mtime = try e.effectiveVersion(matching: query) {
        let date = getDateString(seconds: mtime)
        if verbose {
            print("# Last-Modified: \(date)")
        }
    }
    let results = try e.evaluate(query: query)
    switch results {
    case .bindings(_, let iter):
        for result in iter {
            count += 1
            print("\(count)\t\(result.description)")
        }
    case .boolean(let v):
        print("\(v)")
    case .triples(let iter):
        for triple in iter {
            count += 1
            print("\(count)\t\(triple.description)")
        }
    }
    
    if verbose {
        let endTime = getCurrentTime()
        let elapsed = endTime - startTime
        warn("query time: \(elapsed)s")
    }
    return count
}

func data(fromFileOrString qfile: String) throws -> Data {
    let url = URL(fileURLWithPath: qfile)
    let data: Data
    if case .some(true) = try? url.checkResourceIsReachable() {
        data = try Data(contentsOf: url)
    } else {
        guard let s = qfile.data(using: .utf8) else {
            fatalError("Could not interpret SPARQL query string as UTF-8")
        }
        data = s
    }
    return data
}

var verbose = true
let argscount = CommandLine.arguments.count
var args = PeekableIterator(generator: CommandLine.arguments.makeIterator())
guard let pname = args.next() else { fatalError("Missing command name") }
guard argscount >= 1 else {
    print("Usage: \(pname) [-v] QUERY")
    print("")
    exit(1)
}

if let next = args.peek(), next == "-v" {
    _ = args.next()
    verbose = true
}

guard let qfile = args.next() else { fatalError("No query file given") }
let graph = Term(iri: "http://example.org/")


let startTime = getCurrentTime()
let startSecond = getCurrentDateSeconds()
var count = 0


do {
//    let sparql = try data(fromFileOrString: qfile)
    let sparql = "PREFIX foaf: <http://xmlns.com/foaf/0.1/> SELECT * WHERE { ?s a ?type ; foaf:name ?name }".data(using: .utf8)!
    guard var p = SPARQLParser(data: sparql) else { fatalError("Failed to construct SPARQL parser") }
    let q = try p.parseQuery()
    count = try query(query: q, graph: graph, verbose: verbose)
} catch let e {
    warn("*** Failed to evaluate query:")
    warn("*** - \(e)")
}

let endTime = getCurrentTime()
let elapsed = Double(endTime - startTime)
let tps = Double(count) / elapsed
if verbose {
    //    Logger.shared.printSummary()
    warn("elapsed time: \(elapsed)s (\(tps)/s)")
}
