"""
Example DAG for Apache Airflow 3
This demonstrates basic DAG creation and tasks.
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator

# Default arguments
default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Define the DAG
dag = DAG(
    'example_dag',
    default_args=default_args,
    description='A simple example DAG for Airflow 3',
    schedule_interval=timedelta(days=1),
    catchup=False,
    tags=['example'],
)

def print_hello():
    """Simple Python function"""
    print("Hello from Airflow 3!")
    return "Hello World"

def print_context(**context):
    """Print the Airflow context"""
    print(f"Execution date: {context['execution_date']}")
    print(f"DAG run: {context['dag_run']}")
    return "Context printed"

# Task 1: Python operator
task_hello = PythonOperator(
    task_id='print_hello',
    python_callable=print_hello,
    dag=dag,
)

# Task 2: Bash operator
task_date = BashOperator(
    task_id='print_date',
    bash_command='date',
    dag=dag,
)

# Task 3: Python operator with context
task_context = PythonOperator(
    task_id='print_context',
    python_callable=print_context,
    dag=dag,
)

# Task 4: Bash operator
task_sleep = BashOperator(
    task_id='sleep',
    bash_command='sleep 5',
    dag=dag,
)

# Task 5: Final task
task_done = BashOperator(
    task_id='done',
    bash_command='echo "DAG completed successfully!"',
    dag=dag,
)

# Set task dependencies
task_hello >> task_date >> task_context >> task_sleep >> task_done
