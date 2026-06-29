FROM python:3.9-slim

WORKDIR /app

RUN pip install --no-cache-dir openpyxl

COPY make_server_spec_excel.py /scripts/make_server_spec_excel.py

CMD ["python3", "/scripts/make_server_spec_excel.py"]
