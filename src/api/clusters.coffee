_ = require('underscore')
Promise = require('pantheon-helpers/lib/promise')
instances = require('./instances')
couch_utils = require('../couch_utils')
uuid = require('node-uuid')

doAction = require('pantheon-helpers/lib/doAction')

clusters = {}

clusters.get_cluster = (db_client, cluster_id, callback) ->
  db_client.use('moirai').get(cluster_id, callback)

clusters.handle_get_cluster = (req, resp) ->
  cluster_id = 'cluster_' + req.params.cluster_id
  clusters.get_cluster(req.couch, cluster_id).pipe(resp)

clusters.get_clusters = (db_client, callback) ->
  params = {include_docs: true}
  db_client.use('moirai').viewWithList('moirai', 'active_clusters', 'get_docs', params, callback)

clusters.handle_get_clusters = (req, resp) ->
  clusters.get_clusters(req.couch).pipe(resp)

clusters.create_cluster = (db, record, callback) ->
  record.instances.forEach((instance) -> instance.id = uuid.v4())
  record.name = "a_cluster"
  return doAction(db, 'moirai', null, {a: 'c+', record: record}, callback)

clusters.handle_create_cluster = (req, resp) ->
  cluster_opts = req.body or {}
  db = req.couch.use('moirai')
  clusters.create_cluster(db, cluster_opts).pipe(resp)


clusters.destroy_cluster = (db, cluster_id, callback) ->
  return doAction(db, 'moirai', cluster_id, {a: 'c-'}, callback)

clusters.handle_destroy_cluster = (req, resp) ->
  cluster_id = "cluster_" + req.params.cluster_id
  db = req.couch.use('moirai')
  clusters.destroy_cluster(db, cluster_id).pipe(resp)


clusters.add_instance = (db_client, cluster_id, instance_opts) ->
  instances.create_instance(instance_opts).then((data) ->
    clusters.get_cluster(db_client, cluster_id).then((cluster) ->
      cluster.instances.push(data)
      Promise.denodeify(couch_utils.ensure_db)(db_client, 'insert', cluster).then(() ->
        # Return the new instance
        Promise.resolve(data)
      )
    ).catch((err) ->
      # TODO handle error updating DB
      Promise.reject(err)
    )
  )

clusters.handle_add_instance = (req, resp) ->
  cluster_id = req.params.cluster_id
  instance_opts = req.body or {}
  client = req.couch.use('moirai')
  clusters.add_instance(client, cluster_id, instance_opts).then((couch_resp) ->
    return resp.status(201).send(JSON.stringify(couch_resp))
  ).catch((err) ->
    return resp.status(500).send(JSON.stringify({error: 'internal error', msg: String(err)}))
  )

clusters.handle_update_cluster = (req, resp) ->
  resp.send('NOT IMPLEMENTED')

module.exports = clusters
