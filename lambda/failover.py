import boto3
import os
import json
import time
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DR_REGION       = os.environ['DR_REGION']
DR_ASG_NAME     = os.environ['DR_ASG_NAME']
DR_REPLICA_ID   = os.environ['DR_REPLICA_ID']
DR_ASG_CAPACITY = int(os.environ.get('DR_ASG_CAPACITY', '2'))
SNS_TOPIC_ARN   = os.environ['SNS_TOPIC_ARN']

rds_client = boto3.client('rds',         region_name=DR_REGION)
asg_client = boto3.client('autoscaling', region_name=DR_REGION)
sns_client = boto3.client('sns')


def lambda_handler(event, context):
    logger.info(f"DR Failover triggered. Event: {json.dumps(event)}")
    results = {}

    # ── Step 1: Promote RDS Read Replica ─────────────────────────────────────
    try:
        resp      = rds_client.describe_db_instances(DBInstanceIdentifier=DR_REPLICA_ID)
        db        = resp['DBInstances'][0]
        status    = db['DBInstanceStatus']
        is_replica = bool(db.get('ReadReplicaSourceDBInstanceIdentifier'))

        if not is_replica:
            logger.info("Replica already promoted or is not a replica. Skipping.")
            results['rds'] = 'already_standalone'
        else:
            logger.info(f"Promoting replica {DR_REPLICA_ID} (current status: {status})")
            rds_client.promote_read_replica(
                DBInstanceIdentifier=DR_REPLICA_ID,
                BackupRetentionPeriod=7,
                PreferredBackupWindow='02:00-03:00'
            )
            results['rds'] = 'promotion_initiated'
            logger.info("RDS promotion initiated — takes ~5 minutes to complete")

    except Exception as e:
        logger.error(f"RDS promotion error: {e}")
        results['rds_error'] = str(e)

    # ── Step 2: Scale up DR Auto Scaling Group ────────────────────────────────
    try:
        asg_client.update_auto_scaling_group(
            AutoScalingGroupName=DR_ASG_NAME,
            MinSize=DR_ASG_CAPACITY,
            MaxSize=4,
            DesiredCapacity=DR_ASG_CAPACITY
        )
        results['asg'] = f'scaled_to_{DR_ASG_CAPACITY}'
        logger.info(f"DR ASG {DR_ASG_NAME} scaled to desired={DR_ASG_CAPACITY}")

    except Exception as e:
        logger.error(f"ASG scaling error: {e}")
        results['asg_error'] = str(e)

    # ── Step 3: Send SNS notification ─────────────────────────────────────────
    message = {
        'subject':          'DR FAILOVER ACTIVATED',
        'dr_region':        DR_REGION,
        'timestamp':        time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'results':          results,
        'action_required': (
            'DR failover is in progress. '
            'Verify the app at the DR ALB endpoint. '
            'Monitor RDS promotion status in ap-southeast-1 console. '
            'Update app config to point to DR RDS endpoint once promoted.'
        )
    }
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject='DR FAILOVER ACTIVATED',
            Message=json.dumps(message, indent=2)
        )
        results['sns'] = 'notified'
        logger.info("SNS notification sent")

    except Exception as e:
        logger.error(f"SNS notification error: {e}")
        results['sns_error'] = str(e)

    logger.info(f"Failover handler complete. Results: {json.dumps(results)}")
    return {
        'statusCode': 200,
        'body': json.dumps(results)
    }
