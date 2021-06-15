//==============================Setup===============================//
//Create New Database - OPTIONAL (Skip if using Neo4j Sandbox or Desktop)
CREATE DATABASE querytuning;

// Set database to the 'querytuning' database - If the previous step was executed (Skip if using Neo4j Sandbox or Desktop)
:use querytuning

// Load Dataset
// Ingest Movies CSV
LOAD CSV WITH HEADERS FROM 'https://gist.githubusercontent.com/maruthiprithivi/23a210f5c0dc7ba53ac986dfe6f38943/raw/38b4b1f073f459dcd73d7deb5216013f42c05577/movies.csv' AS line
MERGE (m:Movie { title: line.title })
ON CREATE SET m.released = toInteger(line.released), m.tagline = line.tagline

// Ingest Actors CSV
LOAD CSV WITH HEADERS FROM 'https://gist.githubusercontent.com/maruthiprithivi/23a210f5c0dc7ba53ac986dfe6f38943/raw/c6ec516beea4e87d40ce81bb09eeeab6a9551584/actors.csv' AS line
MATCH (m:Movie { title: line.title })
MERGE (p:Person { name: line.person })
ON CREATE SET p.born = toInteger(line.born)
MERGE (p)-[:ACTED_IN { roles:split(line.roles, ';')}]->(m)

// Ingest Directors CSV
LOAD CSV WITH HEADERS FROM 'https://gist.githubusercontent.com/maruthiprithivi/23a210f5c0dc7ba53ac986dfe6f38943/raw/c6ec516beea4e87d40ce81bb09eeeab6a9551584/directors.csv' AS line
MATCH (m:Movie { title: line.title })
MERGE (p:Person { name: line.person })
ON CREATE SET p.born = toInteger(line.born)
MERGE (p)-[:DIRECTED]->(m)

// Check ingested data
// Visualise Graph DB
call db.schema.visualization

// Retrieve a data point
MATCH (p { name: 'Tom Hanks' })
RETURN p
//==============================END===============================//

//==============================Query Tuning===============================//

// Execute PROFILE --> AllNodesScan (Execution Plan)
PROFILE
MATCH (p { name: 'Tom Hanks' })
RETURN p

// A more efficient way to get the same outcome as the previous query, but doing it efficiently
MATCH (p:Person { name: 'Tom Hanks' })
RETURN p

// Execute PROFILE - Let's take a look why this is more effcient? --> NodeByLabelScan (Execution Plan)
PROFILE
MATCH (p:Person { name: 'Tom Hanks' })
RETURN p

// To further improve the query performance, we add indexes to the Node properties
CREATE INDEX personName FOR (p:Person)
ON (p.name)

// Verify the index created
call db.indexes

// Executing the Match query for Tom Hanks after indexing the name property for Person Node
MATCH (p:Person { name: 'Tom Hanks' })
RETURN p

// Execute PROFILE - This is much more efficient from the first time we looked up Tom Hanks! --> NodeIndexSeek (Execution Plan)
PROFILE
MATCH (p:Person { name: 'Tom Hanks' })
RETURN p

// Let's look at Index-backed property-lookup
// Predicate
// Look for Tom's in the Graph
MATCH (p:Person)-[:ACTED_IN]->(m:Movie)
WHERE p.name STARTS WITH 'Tom'
RETURN p.name, count(m)

// Execute PROFILE - You will notice the query plan starts with setting the Anchor nodes 
// and leveraging the cached data for the property "person.name"
PROFILE
MATCH (p:Person)-[:ACTED_IN]->(m:Movie)
WHERE p.name STARTS WITH 'Tom'
RETURN p.name, count(m)

// How does the query plan look when we don't use any index 
// Similar to previous query but without the predicate to narrow down on Tom's
// Notice the NodeIndexSeek... has been replaced by NodeByLabelScan and the
// aggregation step the operator is reading from the DB to retrieve the properties
PROFILE
MATCH (p:Person)-[:ACTED_IN]->(m:Movie)
RETURN p.name, count(m)

// Aggregation 
// Notice NodeIndexScan check the "p.name" property from cache and aggregation has 0 DB hits!
PROFILE
MATCH (p:Person)
RETURN count(DISTINCT p.name) AS numberOfNames

// Order by 
// The native index happens to store String properties in ascending alphabetical order, and Cypher knows this.
PROFILE
MATCH (p:Person)-[:ACTED_IN]->(m:Movie)
WHERE p.name STARTS WITH 'Tom'
RETURN p.name, count(m)
ORDER BY p.name

// Min & Max Optimiser
// For the min and max functions, the index-backed order by optimization can be used to avoid aggregation 
// and instead utilize the fact that the minimum/maximum value is the first/last one in a sorted index
PROFILE
MATCH (p:Person)-[:ACTED_IN]->(m:Movie)
RETURN min(p.name) AS name

//==============================END===============================//

//==============================Note (Restrictions)===============================//
// 
// The optimization can only work on native indexes. It does not work for predicates only querying for the spatial type Point. 
// Predicates that can be used to enable this optimization are:
// Existence (e.g.WHERE exists(n.name))
// Equality (e.g. WHERE n.name = 'Tom Hanks')
// Range (e.g. WHERE n.uid > 1000 AND n.uid < 2000)
// Prefix (e.g. WHERE n.name STARTS WITH 'Tom')
// Suffix (e.g. WHERE n.name ENDS WITH 'Hanks')
// Substring (e.g. WHERE n.name CONTAINS 'a')

// Predicates that will not work:
// Several predicates combined using OR
// Equality or range predicates querying for points (e.g. WHERE n.place > point({ x: 1, y: 2 }))
// Spatial distance predicates (e.g. WHERE distance(n.place, point({ x: 1, y: 2 })) < 2)
//==============================END===============================//