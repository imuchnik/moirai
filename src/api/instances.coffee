_ = require('underscore')
Promise = require('pantheon-helpers/lib/promise')
aws = require('aws-sdk')
conf = require('../config')

# Get only the fields we want from an instance object
# Instances from aws-sdk are bundled inside of a list
# of reservation objects
prepareInstances = (resp_object) ->
  fields = [
    'InstanceId',
    'InstanceType',
    'PrivateIpAddress',
    'State',
    'Tags',
  ]

  instance_list = []

  if resp_object.Reservations != undefined
    for reservation in resp_object.Reservations
      for instance in reservation.Instances
        instance_list.push _.pick(instance, fields...)
  else
    for instance in resp_object.Instances
      instance_list.push _.pick(instance, fields...)
  return instance_list

instances = {}

ec2PromiseClient = (ec2_opts) ->
  ec2 = new aws.EC2(ec2_opts)
  client = {}
  ['createTags', 'describeInstances', 'runInstances', 'terminateInstances'].forEach((method) ->
    client[method] = Promise.denodeify(ec2[method]).bind(ec2)
  )
  return client

ec2 = ec2PromiseClient({
  apiVersion: conf.AWS.APIVERSION,
  accessKeyId: conf.AWS.ACCESS_KEY,
  secretAccessKey: conf.AWS.SECRET_KEY,
  region: conf.AWS.REGION
})

instances.create_instance = (opts) ->
  instance_params =
    InstanceType: conf.AWS.INSTANCETYPE

  required_params =
    ImageId: conf.AWS.IMAGEID
    MaxCount: 1
    MinCount: 1
    KeyName: conf.AWS.KEYNAME
    SubnetId: conf.AWS.SUBNETID
    SecurityGroupIds: conf.AWS.SECURITYGROUPIDS
  user_params = _.pick(opts, 'InstanceType')
  _.extend(instance_params, user_params, required_params)

  # TODO should there be config defaults? none of these
  # should be hardcoded
  tags =
    Name: "AWSDEVMOIRAI", # TODO generate this
    Application: '',
    Owner: 'default.user@example.com', # TODO figure this out
    Cluster: 'moirai',
    Description: '',

  # TODO should we blindly accept tags? Only tags we plan on
  # Using? what if there are more than 10?
  user_tags = _.pick(opts.tags, 'Application', 'Name')

  # TODO should there be config defaults? none of these
  # should be hardcoded
  required_tags =
    Domain: 'dev',
    Role: '',
    CreateDate: new Date().toISOString().split('T')[0]

  _.extend(tags, user_tags, required_tags)

  # TODO find a better way to insert values to user data
  user_data = conf.AWS.USERDATA
  user_data = user_data.replace('<HOSTNAME>', tags.Name)

  instance_params.UserData = new Buffer(user_data).toString('base64')

  # create instance via AWS API
  ec2.runInstances(instance_params).then((data) ->
    tag_params = 
      Resources: [data.Instances[0].InstanceId],
      Tags: ({'Key': key, 'Value': value} for key,value of tags)
    preparedInstance = prepareInstances(data)[0]

    ec2.createTags(tag_params).catch((err) ->
      # What do we do here? delete the instance?
      Promise.reject(err)
    ).then(() ->
      preparedInstance.Tags = tag_params.Tags
      Promise.resolve(preparedInstance)
    )
  )

instances.handle_create_instance = (req, resp) ->
  all_opts = req.body or {}
  instances.create_instance(req.couch, all_opts).then((cluster_doc) ->
    return resp.status(201).send(JSON.stringify(cluster_doc))
  ).catch((err) ->
    return resp.status(500).send(JSON.stringify({error: 'internal error', msg: String(err)}))
  )

instances.get_instances = () ->
  params = {
    Filters: [
      {
          Name: 'key-name',
          Values: [
            # TODO consider a better way of pulling moirai machines.
            # With this solution, changing the config key will "lose"
            # any existing instances
            conf.AWS.KEYNAME
          ]
      },
      {
          Name: 'instance-state-name',
          Values: ['pending', 'running', 'stopping', 'stopped']
      }
    ]
  }
  ec2.describeInstances(params).then((data) ->
    Promise.resolve(prepareInstances(data))
  )

instances.handle_get_instances = (req, resp) ->
  instances.get_instances().then((data) ->
    return resp.status(201).send(JSON.stringify(data))
  ).catch((err) ->
    return resp.status(500).send(JSON.stringify({error: 'internal error', msg: String(err)}))
  )

instances.get_instance = (instance_id) ->
  params = {
    InstanceIds: [instance_id]
    Filters: [
      {
          Name: 'key-name',
          Values: [
            # TODO consider a better way of pulling moirai machines.
            # With this solution, changing the config key will "lose"
            # any existing instances
            conf.AWS.KEYNAME
          ]
      },
      {
          Name: 'instance-state-name',
          Values: ['pending', 'running', 'stopping', 'stopped']
      }
    ]
  }

  ec2.describeInstances(params).then((data) ->
    if not data.Reservations.length
      return Promise.reject('Unrecognized instance ID: ' + instance_id)
    Promise.resolve(prepareInstances(data)[0])
  )

instances.handle_get_instance = (req, resp) ->
  instance_id = req.params.instance_id
  instances.get_instance(instance_id).then((data) ->
    return resp.status(201).send(JSON.stringify(data))
  ).catch((err) ->
    return resp.status(500).send(JSON.stringify({error: 'internal error', msg: String(err)}))
  )


instances.handle_update_instance = (req, resp) ->
  # TODO determine what updates are available
  # name
  # instance type (requires shutdown)
  resp.send('NOT IMPLEMENTED')

instances.destroy_instance = (instance_id) ->
  params = {
    InstanceIds: [instance_id]
  }

  ec2.terminateInstances(params)


instances.handle_destroy_instance = (req, resp) ->
  instance_id = req.params.instance_id
  instances.destroy_instance(instance_id).then((data) ->
    return resp.status(201).send(JSON.stringify(data))
  ).catch((err) ->
    return resp.status(500).send(JSON.stringify({error: 'internal error', msg: String(err)}))
  )

module.exports = instances
