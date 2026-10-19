FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py index.html ./

# so pra mostrar os prints na hora nos logs
ENV PYTHONUNBUFFERED=1

# porta interna, nao e publicada pro host (quem expoe e o nginx)
EXPOSE 5000

CMD ["python", "app.py"]
