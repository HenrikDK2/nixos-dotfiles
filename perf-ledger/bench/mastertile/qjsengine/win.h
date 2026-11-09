#pragma once
#include <QObject>
#include <QRectF>
class Tile : public QObject {
    Q_OBJECT
    Q_PROPERTY(QRectF absoluteGeometry READ absoluteGeometry CONSTANT)
public:
    QRectF absoluteGeometry() const { return QRectF(0,0,960,1080); }
};
class Win : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool fullScreen READ fullScreen NOTIFY fullScreenChanged)
    Q_PROPERTY(bool minimized READ minimized NOTIFY minimizedChanged)
    Q_PROPERTY(bool move READ move NOTIFY moveResizedChanged)
    Q_PROPERTY(bool resize READ resize NOTIFY moveResizedChanged)
    Q_PROPERTY(Tile* tile READ tile WRITE setTile NOTIFY tileChanged)
    Q_PROPERTY(QRectF frameGeometry READ frameGeometry NOTIFY frameGeometryChanged)
public:
    bool fs=false, mini=false, mv=false, rs=false; Tile* t=nullptr; QRectF g{10,10,500,400};
    bool fullScreen() const { return fs; }
    bool minimized() const { return mini; }
    bool move() const { return mv; }
    bool resize() const { return rs; }
    Tile* tile() const { return t; }
    void setTile(Tile* x){ t=x; emit tileChanged(); }
    QRectF frameGeometry() const { return g; }
    void fire(){ QRectF old=g; g.translate(1,0); emit frameGeometryChanged(old); }
signals:
    void fullScreenChanged(); void minimizedChanged(); void moveResizedChanged();
    void tileChanged(); void frameGeometryChanged(const QRectF &oldGeometry);
};
